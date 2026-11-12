import BackgroundTasks
import Foundation
import JellyfinKit
import Network
import UIKit

/// The iPhone's `DownloadTransfer`: one background `URLSession`, Wi-Fi only, that keeps going
/// while the app is suspended or closed. It also watches the network (Waiting for Wi-Fi, back
/// online) and runs the background refresh that keeps Downloads for you topped up.
final class DownloadManager: NSObject, DownloadTransfer, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = DownloadManager()
    static let sessionIdentifier = "app.tinyjellyfin.Tinyfin.downloads"
    static let refreshIdentifier = "app.tinyjellyfin.Tinyfin.refresh"

    /// Set once at launch; read from the session's queue to place finished files.
    private(set) var store: DownloadStore?
    @MainActor private weak var downloads: Downloads?
    /// Handed over by the app delegate when iOS wakes the app for this session's events.
    @MainActor var backgroundCompletion: (() -> Void)?

    private let lock = NSLock()
    private var badStatus: [String: Int] = [:]
    private var lastProgress: [String: Date] = [:]
    private let monitor = NWPathMonitor()

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.allowsCellularAccess = false
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    /// Connects to the session (and its transfers from earlier launches) and the network monitor.
    @MainActor func activate(_ downloads: Downloads) {
        self.downloads = downloads
        store = downloads.store
        downloads.transfer = self
        _ = session
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let wifi = online && path.usesInterfaceType(.wifi)
            Task { @MainActor in
                guard let downloads = self?.downloads else { return }
                let cameBack = online && !downloads.isOnline
                downloads.isOnline = online
                downloads.waitingForWiFi = !wifi
                if cameBack { await downloads.sync() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "app.tinyjellyfin.network"))
    }

    // MARK: DownloadTransfer

    func begin(id: String, request: URLRequest, resumeData: Data?, destination: URL) {
        let task = resumeData.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: request)
        task.taskDescription = id
        task.resume()
    }

    func cancel(id: String) {
        session.getAllTasks { tasks in tasks.filter { $0.taskDescription == id }.forEach { $0.cancel() } }
    }

    func cancelAll() {
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        // A few updates a second are plenty for a progress ring.
        let due = lock.withLock {
            guard Date().timeIntervalSince(lastProgress[id] ?? .distantPast) > 0.5 else { return false }
            lastProgress[id] = Date()
            return true
        }
        guard due else { return }
        Task { @MainActor in self.downloads?.progress(id, received: totalBytesWritten) }
    }

    /// The temporary file is deleted when this returns, so it is moved into place here.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 206 else {
            lock.withLock { badStatus[id] = status }   // the body is the server's error, not the film
            return
        }
        guard let store, let record = store.record(id: id) else { return }
        let destination = store.file(id, record.mediaFile)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: location, to: destination)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription else { return }
        lock.withLock { lastProgress[id] = nil }
        let status = lock.withLock { badStatus.removeValue(forKey: id) }
        if let error {
            let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            Task { @MainActor in await self.downloads?.failed(id, error: error, resumeData: resumeData) }
        } else if let status {
            Task { @MainActor in await self.downloads?.failed(id, error: JellyfinError.server(status: status, message: nil), resumeData: nil) }
        } else {
            Task { @MainActor in await self.downloads?.finished(id) }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.backgroundCompletion?()
            self.backgroundCompletion = nil
        }
    }

    // MARK: Background refresh

    /// Must run before the app finishes launching.
    func registerRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshIdentifier, using: nil) { task in
            self.scheduleRefresh()
            let work = Task { @MainActor in
                await self.downloads?.sync()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// Asks iOS for a refresh in six hours at the earliest; it decides when.
    func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
