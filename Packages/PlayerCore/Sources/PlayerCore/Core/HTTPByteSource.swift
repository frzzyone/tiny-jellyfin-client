import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPStatusError: LocalizedError, CustomStringConvertible {
    public let status: Int
    public var description: String { "HTTP \(status)" }
    public var errorDescription: String? { "The server answered HTTP \(status)." }
}

/// Streams an HTTP resource with Range requests through URLSession: system TLS, proxies,
/// and an Authorization header per request (tokens never go into URLs).
/// Sequential reads come from one streaming response; a seek restarts at the new offset.
/// Network drops are retried from the current offset (1 s, 2 s, 4 s). When far enough ahead
/// of the reader the download is dropped (not suspended: an idle connection would hit the
/// request timeout) and resumed with a new Range request when the reader catches up.
public final class HTTPByteSource: ByteSource, @unchecked Sendable {
    public static let retryDelays: [TimeInterval] = [1, 2, 4]
    /// Statuses that mean "try again shortly": timeouts, rate limits, and a proxy that can't
    /// reach the server.
    static let retriedStatuses: Set<Int> = [408, 429, 502, 503, 504]
    static let defaultMaxBuffered = 16 * 1024 * 1024
    /// Forward gaps smaller than this are read through instead of reconnecting.
    static let skipWindow: Int64 = 1024 * 1024

    let url: URL
    let headers: [String: String]
    let session: URLSession
    var retryDelays = HTTPByteSource.retryDelays
    var readTimeout: TimeInterval = 60
    /// Bytes buffered ahead of the reader before the download is parked.
    var maxBuffered = HTTPByteSource.defaultMaxBuffered

    private let condition = NSCondition()
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var bufferOffset: Int64 = 0
    private var skipRemaining: Int64 = 0
    private var finished = false
    private var failure: Error?
    /// The download was stopped because the buffer was full; resume at the buffer's end.
    private var parked = false
    private var knownSize: Int64?
    private var interruptGeneration = 0
    private var closed = false
    private var requestStarted = Date()

    public init(url: URL, headers: [String: String], session: URLSession) {
        self.url = url
        self.headers = headers
        self.session = session
    }

    deinit { close() }

    /// One session for every stream: a session with a delegate lives until it is invalidated, so
    /// one per demuxer would leak.
    public static let sharedSession = makeSession()

    public static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config, delegate: HTTPStreamRouter.shared, delegateQueue: nil)
    }

    public var size: Int64? {
        condition.lock(); defer { condition.unlock() }
        return knownSize
    }

    public func read(at offset: Int64, maxLength: Int) throws -> Data {
        condition.lock()
        defer { condition.unlock() }
        let generation = interruptGeneration
        var attempt = 0
        if let size = knownSize, offset >= size { return Data() }

        while true {
            if closed || generation != interruptGeneration { throw ByteSourceCancelled() }
            let end = bufferOffset + Int64(buffer.count)
            let positionedHere = (task != nil || parked) && failure == nil && offset >= bufferOffset
                && offset <= end + Self.skipWindow
            if !positionedHere {
                if let failure, !(failure is ByteSourceCancelled) {
                    // Retry from where we are, unless the error is a definitive HTTP status. A 500
                    // is the server failing (Jellyfin's FFmpeg would not start), not a busy gateway.
                    if let status = failure as? HTTPStatusError, !Self.retriedStatuses.contains(status.status) {
                        throw failure
                    }
                    guard attempt < retryDelays.count else { throw failure }
                    let delay = retryDelays[attempt]
                    attempt += 1
                    _ = condition.wait(until: Date().addingTimeInterval(delay))
                    if closed || generation != interruptGeneration { throw ByteSourceCancelled() }
                }
                start(at: offset)
            }

            // Wait for bytes at `offset`.
            let deadline = Date().addingTimeInterval(readTimeout)
            while true {
                if closed || generation != interruptGeneration { throw ByteSourceCancelled() }
                let available = bufferOffset + Int64(buffer.count) - offset
                if offset >= bufferOffset && available > 0 { break }
                if finished { return Data() }
                if failure != nil { break }
                if parked { start(at: offset) }
                if !condition.wait(until: deadline) {
                    failure = URLError(.timedOut)
                    break
                }
            }
            if failure != nil && !(offset >= bufferOffset && bufferOffset + Int64(buffer.count) > offset) {
                task?.cancel()
                task = nil
                continue
            }

            // Serve from the buffer, dropping everything before `offset`.
            let drop = Int(offset - bufferOffset)
            if drop > 0 {
                buffer.removeFirst(drop)
                bufferOffset = offset
            }
            let count = min(maxLength, buffer.count)
            let chunk = buffer.prefix(count)
            buffer.removeFirst(count)
            bufferOffset += Int64(count)
            return Data(chunk)
        }
    }

    /// Makes a blocked `read` throw `ByteSourceCancelled`. The next read reconnects.
    public func cancel() {
        condition.lock()
        interruptGeneration += 1
        task?.cancel()
        task = nil
        condition.broadcast()
        condition.unlock()
    }

    public func close() {
        condition.lock()
        closed = true
        task?.cancel()
        task = nil
        condition.broadcast()
        condition.unlock()
    }

    // Called with the lock held.
    private func start(at offset: Int64) {
        task?.cancel()
        var request = URLRequest(url: url)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
        buffer.removeAll(keepingCapacity: true)
        bufferOffset = offset
        skipRemaining = 0
        finished = false
        failure = nil
        parked = false
        requestStarted = Date()
        PlayerLog.network("GET \(url.path) from byte \(offset)")
        let task = session.dataTask(with: request)
        HTTPStreamRouter.shared.register(task, for: self)
        self.task = task
        task.resume()
    }

    // MARK: Delegate callbacks (from the router)

    fileprivate func received(response: URLResponse, task: URLSessionDataTask) -> Bool {
        condition.lock(); defer { condition.unlock() }
        guard task === self.task else { return false }
        guard let http = response as? HTTPURLResponse else { return true }
        PlayerLog.network("HTTP \(http.statusCode) after \(String(format: "%.2f", Date().timeIntervalSince(requestStarted))) s"
                          + " \(url.path) from byte \(bufferOffset)"
                          + " length=\(http.expectedContentLength)"
                          + " range=\(http.value(forHTTPHeaderField: "Content-Range") ?? "-")")
        switch http.statusCode {
        case 206:
            if let range = http.value(forHTTPHeaderField: "Content-Range"),
               let total = range.split(separator: "/").last.flatMap({ Int64($0) }) {
                knownSize = total
            }
        case 200:
            if http.expectedContentLength > 0 { knownSize = http.expectedContentLength }
            // Server ignored the Range header: skip up to the requested offset.
            skipRemaining = bufferOffset
        case 416:
            finished = true
            condition.broadcast()
            return false
        default:
            failure = HTTPStatusError(status: http.statusCode)
            condition.broadcast()
            return false
        }
        return true
    }

    fileprivate func received(data: Data, task: URLSessionDataTask) {
        condition.lock()
        guard task === self.task else { condition.unlock(); return }
        var data = data
        if skipRemaining > 0 {
            let skip = Int(min(Int64(data.count), skipRemaining))
            data.removeFirst(skip)
            skipRemaining -= Int64(skip)
        }
        buffer.append(data)
        let parkNow = buffer.count > maxBuffered
        if parkNow {
            // Far enough ahead: drop the connection and pick up from here later.
            parked = true
            self.task = nil
        }
        condition.broadcast()
        condition.unlock()
        // Cancel outside the lock: URLSession may deliver the completion synchronously.
        if parkNow {
            PlayerLog.network("Parked \(url.path): buffer full")
            task.cancel()
        }
    }

    fileprivate func completed(task: URLSessionTask, error: Error?) {
        condition.lock(); defer { condition.unlock() }
        guard task === self.task else { return }
        if let error {
            if (error as? URLError)?.code != .cancelled, failure == nil {
                // The code only: URLSession's error carries the URL, and a transcode's URLs carry
                // the access token (`api_key`); this error ends up in logs and on screen.
                failure = (error as? URLError).map { URLError($0.code) } ?? error
                PlayerLog.network("HTTP error \(url.path) at byte \(bufferOffset + Int64(buffer.count)): \(error.localizedDescription)")
            }
        } else if failure == nil {
            finished = true
        }
        condition.broadcast()
    }
}

/// Session delegate that routes streaming callbacks to the owning `HTTPByteSource`.
final class HTTPStreamRouter: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let shared = HTTPStreamRouter()
    private let lock = NSLock()
    private var owners: [ObjectIdentifier: WeakSource] = [:]

    private struct WeakSource { weak var source: HTTPByteSource? }

    func register(_ task: URLSessionTask, for source: HTTPByteSource) {
        lock.lock(); owners[ObjectIdentifier(task)] = WeakSource(source: source); lock.unlock()
    }

    private func owner(_ task: URLSessionTask) -> HTTPByteSource? {
        lock.lock(); defer { lock.unlock() }
        return owners[ObjectIdentifier(task)]?.source
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let proceed = owner(dataTask)?.received(response: response, task: dataTask) ?? false
        completionHandler(proceed ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        owner(dataTask)?.received(data: data, task: dataTask)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        owner(task)?.completed(task: task, error: error)
        lock.lock(); owners[ObjectIdentifier(task)] = nil; lock.unlock()
    }
}
