import Foundation
import JellyfinKit
import Observation
import PlayerCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Moves the bytes: on the iPhone a background `URLSession` (`DownloadManager`). It saves a
/// finished file at `destination` before calling `Downloads.finished`, since the system deletes
/// its temporary file afterwards.
protocol DownloadTransfer: AnyObject {
    func begin(id: String, request: URLRequest, resumeData: Data?, destination: URL)
    func cancel(id: String)
    func cancelAll()
}

/// The server calls downloads need.
protocol DownloadServer: ProgressServer {
    /// What PlaybackInfo offers at the download quality: the original (Direct Play) or a copy.
    func resolveDownload(_ item: BaseItem) async throws -> ResolvedStream
    func item(id: String) async throws -> BaseItem
    func nextUp(limit: Int, seriesId: String?) async throws -> [BaseItem]
    func resumeItems(limit: Int) async throws -> [BaseItem]
    func endEncoding(playSessionId: String) async throws
    /// A request for one of the server's URLs, signed in.
    func request(_ url: URL) -> URLRequest
    func subtitleURL(itemId: String, mediaSourceId: String, streamIndex: Int, picture: Bool) -> URL
    func posterURL(for item: BaseItem) -> URL?
}

/// Films and episodes on the phone: starting, finishing, retrying and deleting downloads, sending
/// back what was watched, Smart Downloads and Downloads for you.
@MainActor
@Observable
final class Downloads {
    private(set) var records: [DownloadRecord] = []
    /// Bytes received so far, for downloads under way.
    private(set) var received: [String: Int64] = [:]
    /// No Wi-Fi: downloads wait (the session only uses Wi-Fi).
    var waitingForWiFi = false
    /// Any network at all; without one the app opens on Downloads.
    var isOnline = true
    /// The download being played: never deleted from under the player.
    var playingId: String?

    @ObservationIgnored let store: DownloadStore
    @ObservationIgnored private var queue: ProgressQueue
    @ObservationIgnored weak var transfer: DownloadTransfer?
    @ObservationIgnored var server: () -> DownloadServer?
    @ObservationIgnored var freeBytes: () -> Int64 = { Downloads.volumeFreeBytes() }
    /// Reads a finished file's start and length (`MediaFileInfo.read` in the app).
    @ObservationIgnored var probe: (URL) throws -> (start: Double, duration: Double?)
    @ObservationIgnored private var syncing = false
    /// Tries for a server copy before giving up: each is a full new encode.
    static let copyAttempts = 3

    init(store: DownloadStore, server: @escaping () -> DownloadServer?,
         probe: @escaping (URL) throws -> (start: Double, duration: Double?)) {
        self.store = store
        self.server = server
        self.probe = probe
        queue = ProgressQueue(url: store.root.appendingPathComponent("progress.json"))
        records = store.records()
    }

    func record(_ id: String) -> DownloadRecord? { records.first { $0.id == id } }

    /// 0...1 for a download under way. A copy's size is an estimate, so it stops at 99% until done.
    func fraction(_ record: DownloadRecord) -> Double {
        if record.isDone { return 1 }
        guard record.expectedBytes > 0 else { return 0 }
        return min(0.99, Double(received[record.id] ?? record.receivedBytes) / Double(record.expectedBytes))
    }

    /// The service the player uses for a finished download, with the freshest position the phone
    /// knows: viewing not yet sent, else the card's.
    func playbackService(for item: BaseItem) -> LocalPlaybackService? {
        guard let record = record(item.id), record.isDone else { return nil }
        var userData = item.userData ?? record.item.userData
        if let entry = queue.entries[item.id] {
            userData = UserItemData(playbackPositionTicks: Ticks.from(seconds: entry.positionSeconds), played: entry.played)
        }
        return LocalPlaybackService(record: record, folder: store.folder(record.id), userData: userData) { [weak self] id, position, stopped in
            Task { @MainActor in self?.played(id, position: position, stopped: stopped) }
        }
    }

    // MARK: Starting

    func download(_ item: BaseItem, kind: DownloadRecord.Kind = .user) async {
        guard record(item.id) == nil, let server = server() else { return }
        let full = (try? await server.item(id: item.id)) ?? item
        // What it will be is settled by the server when the download begins.
        let record = DownloadRecord(item: full, kind: kind, isCopy: !DownloadSize.isOriginal(full),
                                    mediaFile: "media", expectedBytes: DownloadSize.estimate(full) ?? 0)
        save(record)
        await startNext()
    }

    /// Begins queued downloads: originals at once, server copies one at a time (each is a full
    /// encode on the server).
    func startNext() async {
        guard let server = server(), let transfer else { return }
        for record in records where record.status == .queued {
            if record.isCopy && records.contains(where: { $0.status == .downloading && $0.isCopy }) { continue }
            await begin(record, server: server, transfer: transfer)
        }
    }

    private func begin(_ queued: DownloadRecord, server: DownloadServer, transfer: DownloadTransfer, resumeData: Data? = nil) async {
        var record = queued
        do {
            let stream = try await server.resolveDownload(record.item)
            guard self.record(record.id) != nil else {   // deleted meanwhile
                if let session = stream.playSessionId { try? await server.endEncoding(playSessionId: session) }
                return
            }
            record.isCopy = stream.playMethod != .directPlay
            record.playSessionId = record.isCopy ? stream.playSessionId : nil
            let container = (stream.mediaSource.container ?? "mkv").split(separator: ",").first.map(String.init) ?? "mkv"
            record.mediaFile = "media." + (record.isCopy ? "ts" : container)
            let subtitles = Self.subtitlesToFetch(stream.mediaSource, isCopy: record.isCopy)
            record.item.mediaSources = [DownloadedSource.make(stream.mediaSource, isCopy: record.isCopy, audio: nil,
                                                              subtitles: Set(subtitles.map(\.index)))]
            record.expectedBytes = record.isCopy ? (DownloadSize.copy(record.item) ?? record.expectedBytes)
                                                 : (stream.mediaSource.size ?? record.expectedBytes)
            guard freeBytes() > record.expectedBytes + 500_000_000 else {
                record.status = .failed("Not enough space on this iPhone")
                save(record)
                return
            }
            record.status = .downloading
            save(record)
            PlayerLog.network("Download: \(record.id) \(record.isCopy ? "server copy" : "original"), ~\(record.expectedBytes / 1_000_000) MB")
            transfer.begin(id: record.id, request: server.request(stream.url), resumeData: resumeData,
                           destination: store.file(record.id, record.mediaFile))
            await fetchExtras(record, subtitles: subtitles, server: server)
        } catch {
            record.status = .failed(Self.describe(error))
            save(record)
        }
    }

    /// Text tracks the copy can't carry (all of them for a copy, the external ones for an
    /// original), and a copy's default picture track when the server has it extracted.
    static func subtitlesToFetch(_ source: MediaSourceInfo, isCopy: Bool) -> [(index: Int, picture: Bool)] {
        source.subtitleStreams.compactMap { stream in
            if !isCopy && stream.isExternal != true { return nil }
            if !stream.isImageSubtitle { return (stream.index, false) }
            return isCopy && stream.index == source.defaultSubtitleStreamIndex ? (stream.index, true) : nil
        }
    }

    /// The poster and subtitle files: small, fetched while the app is open. A picture track the
    /// server hasn't extracted yet is simply left out.
    private func fetchExtras(_ record: DownloadRecord, subtitles: [(index: Int, picture: Bool)], server: DownloadServer) async {
        var urls: [(URL, String)] = subtitles.map { sub in
            (server.subtitleURL(itemId: record.id, mediaSourceId: record.source?.id ?? record.id, streamIndex: sub.index, picture: sub.picture),
             LocalPlaybackService.subtitleFile(sub.index, picture: sub.picture))
        }
        if let poster = server.posterURL(for: record.item) { urls.append((poster, LocalPlaybackService.posterFile)) }
        for (url, name) in urls {
            var request = server.request(url)
            request.timeoutInterval = 15
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 == 200, self.record(record.id) != nil else { continue }
            try? data.write(to: store.file(record.id, name), options: .atomic)
        }
        if var updated = self.record(record.id), updated.item.mediaSources != nil {
            // Keep only the subtitle tracks whose files arrived.
            let fetched = Set(subtitles.filter { FileManager.default.fileExists(atPath: store.file(record.id, LocalPlaybackService.subtitleFile($0.index, picture: $0.picture)).path) }.map(\.index))
            let missing = Set(subtitles.map(\.index)).subtracting(fetched)
            if !missing.isEmpty {
                updated.item.mediaSources![0].mediaStreams?.removeAll { $0.type == .subtitle && missing.contains($0.index) }
            }
            save(updated)   // also redraws the lists, which now have the poster
        }
    }

    // MARK: Transfer events

    func progress(_ id: String, received bytes: Int64) { received[id] = bytes }

    /// The file is at its destination: check it, then mark it done.
    func finished(_ id: String) async {
        guard var record = record(id) else { return }
        received[id] = nil
        let url = store.file(id, record.mediaFile)
        let size = store.bytes(id)
        if let session = record.playSessionId, let server = server() {
            Task.detached { try? await server.endEncoding(playSessionId: session) }
        }
        record.playSessionId = nil
        do {
            let info = try probe(url)
            let runtime = Ticks.seconds(record.item.runTimeTicks ?? 0)
            // A copy the server stopped early can still end like a whole response.
            if record.isCopy, runtime > 0, let duration = info.duration, duration < runtime * 0.99 {
                PlayerLog.engine("Download: \(id) ended at \(Int(duration)) s of \(Int(runtime)) s")
                await retry(record, reason: "The server stopped making the copy")
                return
            }
            record.timelineOffset = -info.start
            record.receivedBytes = size
            record.status = .done
            save(record)
            PlayerLog.network(String(format: "Download: %@ done, %lld MB, starts at %.2f s", id, size / 1_000_000, info.start))
        } catch {
            await retry(record, reason: "The file can't be played")
            return
        }
        await startNext()
    }

    /// The transfer failed. An original resumes where it stopped; a copy starts again.
    func failed(_ id: String, error: Error, resumeData: Data?) async {
        guard var record = record(id) else { return }
        PlayerLog.network("Download: \(id) failed: \(error)\(resumeData != nil ? " (can resume)" : "")")
        received[id] = nil
        if (error as? URLError)?.code == .cancelled && resumeData == nil { return }   // deleted by the user
        if (error as NSError).code == NSURLErrorCannotWriteToFile || (error as NSError).code == NSFileWriteOutOfSpaceError {
            record.status = .failed("Not enough space on this iPhone")
            save(record)
            return
        }
        if !record.isCopy, let resumeData, let server = server(), let transfer, record.attempts < 5 {
            record.attempts += 1
            save(record)
            await begin(record, server: server, transfer: transfer, resumeData: resumeData)
            return
        }
        await retry(record, reason: Self.describe(error))
    }

    private func retry(_ failed: DownloadRecord, reason: String) async {
        var record = failed
        try? FileManager.default.removeItem(at: store.file(record.id, record.mediaFile))
        record.attempts += 1
        record.status = record.attempts < Self.copyAttempts ? .queued : .failed(reason)
        save(record)
        await startNext()
    }

    /// Try again after a failure: from the start, with fresh attempts.
    func tryAgain(_ id: String) async {
        guard var record = record(id) else { return }
        record.attempts = 0
        record.status = .queued
        save(record)
        await startNext()
    }

    // MARK: Deleting

    /// Deleted by the user: a pick of Downloads for you isn't picked again.
    func delete(_ id: String, byUser: Bool = true) {
        guard let record = record(id) else { return }
        transfer?.cancel(id: id)
        if let session = record.playSessionId, let server = server() {
            Task.detached { try? await server.endEncoding(playSessionId: session) }
        }
        if byUser && record.kind == .forYou { store.dismissed.insert(id) }
        store.delete(id)
        records.removeAll { $0.id == id }
        received[id] = nil
    }

    /// Signing out: send what can be sent (briefly), then delete everything.
    func signOut() async {
        if let server = server() {
            _ = try? await withTimeout(5) { [queue] in await queue.flush(to: server) }
        }
        transfer?.cancelAll()
        if let server = server() {
            for session in records.compactMap(\.playSessionId) {
                Task.detached { try? await server.endEncoding(playSessionId: session) }
            }
        }
        store.deleteAll()
        queue = ProgressQueue(url: store.root.appendingPathComponent("progress.json"))
        records = []
        received = [:]
    }

    // MARK: Watching and keeping things ready

    /// From the player of a download: kept on the phone, then sent with the rest.
    func played(_ id: String, position: Double, stopped: Bool) {
        let runtime = record(id).map { Ticks.seconds($0.item.runTimeTicks ?? 0) }
        queue.record(itemId: id, positionSeconds: position, runtimeSeconds: runtime)
        if stopped {
            if playingId == id { playingId = nil }
            Task { await sync() }
        }
    }

    /// Sends the progress waiting, then Smart Downloads and Downloads for you. Run at launch, on
    /// return to the foreground, when the network comes back, after a stop, and in the background.
    func sync() async {
        guard !syncing, let server = server() else { return }
        syncing = true
        defer { syncing = false }
        let settled = await queue.flush(to: server)
        for (id, watched) in settled where watched {
            guard let finished = record(id), finished.isDone else { continue }
            let next = finished.item.seriesId == nil ? nil
                : try? await server.nextUp(limit: 1, seriesId: finished.item.seriesId).first
            let swap = DownloadPlanner.afterFinishing(finished, next: next, records: records)
            if let delete = swap.delete, delete != playingId { self.delete(delete, byUser: false) }
            if let (item, kind) = swap.download { await download(item, kind: kind) }
        }
        guard let nextUp = try? await server.nextUp(limit: DownloadPlanner.shows, seriesId: nil),
              let resume = try? await server.resumeItems(limit: 12) else { await startNext(); return }
        store.dismissed = DownloadPlanner.stillDismissed(store.dismissed, nextUp: nextUp, resume: resume)
        let busy = Set(queue.entries.keys).union([playingId].compactMap { $0 })
        let plan = DownloadPlanner.forYou(nextUp: nextUp, resume: resume, records: records, dismissed: store.dismissed,
                                          busy: busy, freeBytes: freeBytes()) { DownloadSize.estimate($0) ?? 0 }
        for id in plan.delete { delete(id, byUser: false) }
        for item in plan.download { await download(item, kind: .forYou) }
        await startNext()
    }

    // MARK: Helpers

    private func save(_ record: DownloadRecord) {
        try? store.save(record)
        if let index = records.firstIndex(where: { $0.id == record.id }) { records[index] = record } else { records.append(record) }
    }

    static func describe(_ error: Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost: return "The connection was lost"
            case .timedOut: return "The server took too long"
            default: break
            }
        }
        if case JellyfinError.server(let status, _) = error { return "The server said \(status)" }
        return error.localizedDescription
    }

    static func volumeFreeBytes() -> Int64 {
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? Int64.max
    }
}

/// `DownloadServer` on the signed-in Jellyfin server.
struct JellyfinDownloadServer: DownloadServer {
    let client: JellyfinClient
    let capabilities: PlaybackCapabilities

    func resolveDownload(_ item: BaseItem) async throws -> ResolvedStream {
        // Subtitle -1: nothing burnt in; the tracks come along as files.
        let response = try await client.playbackInfo(itemId: item.id, quality: .download, capabilities: capabilities,
                                                     startSeconds: 0, mediaSourceId: item.mediaSources?.first?.id,
                                                     subtitleStreamIndex: -1)
        return try client.resolveStream(itemId: item.id, response: response, startSeconds: 0)
    }

    func item(id: String) async throws -> BaseItem { try await client.item(id: id) }
    func nextUp(limit: Int, seriesId: String?) async throws -> [BaseItem] { try await client.nextUp(limit: limit, seriesId: seriesId) }
    func resumeItems(limit: Int) async throws -> [BaseItem] { try await client.resumeItems(limit: limit) }
    func endEncoding(playSessionId: String) async throws { try await client.endEncoding(playSessionId: playSessionId) }
    func userData(itemId: String) async throws -> UserItemData? { try await client.userData(itemId: itemId) }
    func updateUserData(_ itemId: String, positionSeconds: Double, played: Bool, lastPlayed: Date) async throws -> UserItemData {
        try await client.updateUserData(itemId, positionSeconds: positionSeconds, played: played, lastPlayed: lastPlayed)
    }

    func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(client.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        return request
    }

    func subtitleURL(itemId: String, mediaSourceId: String, streamIndex: Int, picture: Bool) -> URL {
        client.externalSubtitleURL(itemId: itemId, mediaSourceId: mediaSourceId, streamIndex: streamIndex,
                                   format: picture ? "sup" : "srt")
    }

    /// The series' poster for an episode (what the Downloads tab shows), else the item's.
    func posterURL(for item: BaseItem) -> URL? {
        if let series = item.seriesId { return client.url("/Items/\(series)/Images/Primary", query: ["maxHeight": "300"]) }
        return client.primaryImageURL(for: item, maxHeight: 300)
    }
}
