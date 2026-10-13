import AVFoundation
import Foundation
import JellyfinKit
import PlayerCore
@testable import TinyJellyfin

final class FakeEngine: PlaybackEngine, @unchecked Sendable {
    let displayLayer = AVSampleBufferDisplayLayer()
    var state: EngineState = .idle
    var currentTime: Double = 0
    var duration: Double? = 600
    var videoSize: CGSize? = CGSize(width: 1920, height: 800)
    var videoFormatDescription: CMVideoFormatDescription?
    var frameRate: Double?
    var tracks: [MediaTrack] = []
    var isPlaying = false
    var volume: Float = 1
    var isMuted = false
    var onEvent: (@MainActor (EngineEvent) -> Void)?

    var prepared: [(MediaSource, Double)] = []
    var switches: [(MediaSource, Double)] = []
    var seeks: [Double] = []
    var embeddedSubtitle: Int?
    var externalCues: [SubtitleCue]?
    var stopped = false
    var prepareError: Error?
    var switchError: Error?
    var switchDelay: TimeInterval = 0

    func prepare(source: MediaSource, startAt: Double) async throws {
        prepared.append((source, startAt))
        if let prepareError { throw prepareError }
        currentTime = startAt
        state = .paused
    }

    func play() { isPlaying = true; state = .playing }
    func pause() { isPlaying = false; state = .paused }

    func seek(to time: Double) async {
        seeks.append(time)
        currentTime = time
    }

    var audioTrackChanges: [Int] = []
    func selectAudioTrack(_ id: Int) async { audioTrackChanges.append(id) }

    func switchSource(_ source: MediaSource, startAt: Double) async throws {
        switches.append((source, startAt))
        if switchDelay > 0 { try await Task.sleep(nanoseconds: UInt64(switchDelay * 1_000_000_000)) }
        if let switchError { throw switchError }
    }

    func selectEmbeddedSubtitle(trackId: Int?) { embeddedSubtitle = trackId }
    func setExternalSubtitles(_ cues: [SubtitleCue]?) { externalCues = cues }
    func subtitleText(at time: Double) -> String? { nil }
    func subtitleBitmap(at time: Double) -> SubtitleBitmap? { nil }
    var displayedFrame: CVPixelBuffer?
    func copyDisplayedFrame() -> CVPixelBuffer? { displayedFrame }
    func stop() { stopped = true; state = .idle }
    var debugSummary: String { "fake state=\(state)" }

    @MainActor func send(_ event: EngineEvent) { onEvent?(event) }
}

final class FakeService: PlaybackService, @unchecked Sendable {
    let lock = NSLock()
    var streamHeaders: [String: String] = ["Authorization": "MediaBrowser Token=\"t\""]
    var serverURL = URL(string: "https://jf.test")!
    var item: BaseItem
    var resolveCalls: [(quality: QualityPreset, start: Double, subtitle: Int?)] = []
    var audioRequests: [Int?] = []
    var nextMethod: PlayMethod = .directPlay
    var resolveError: Error?
    /// The picture subtitle the server burns in when the request names none (its default).
    var serverDefaultBurnIn: Int?
    var srt = "1\n00:00:01,000 --> 00:00:02,000\nServer cue\n"
    private(set) var events: [String] = []
    private var counter = 0

    init(item: BaseItem) { self.item = item }

    func record(_ event: String) { lock.lock(); events.append(event); lock.unlock() }
    var recorded: [String] { lock.lock(); defer { lock.unlock() }; return events }

    func item(id: String) async throws -> BaseItem { item }

    func resolveStream(itemId: String, quality: QualityPreset, capabilities: PlaybackCapabilities, startSeconds: Double,
                       mediaSourceId: String?, subtitleStreamIndex: Int?, audioStreamIndex: Int?) async throws -> ResolvedStream {
        let n = lock.withLock {
            resolveCalls.append((quality, startSeconds, subtitleStreamIndex))
            audioRequests.append(audioStreamIndex)
            counter += 1
            return counter
        }
        if let resolveError { throw resolveError }
        // Like Jellyfin with our profile: a picture subtitle is embedded (drawn by the app) when the
        // file is sent as is, and burnt in when it is transcoded.
        let directPlay = quality.isOriginal && nextMethod == .directPlay
        let burned = directPlay ? nil : (subtitleStreamIndex ?? serverDefaultBurnIn).flatMap { $0 >= 0 ? $0 : nil }
        let method: PlayMethod = burned != nil ? .transcode : (quality.isOriginal ? nextMethod : .transcode)
        return ResolvedStream(url: URL(string: "https://jf.test/stream\(n)")!, playMethod: method,
                              mediaSource: item.mediaSources![0], mediaSourceId: "src",
                              playSessionId: "ps\(n)", timelineOffset: 0, burnedInSubtitle: burned)
    }

    func subtitleData(itemId: String, mediaSourceId: String, streamIndex: Int) async throws -> Data {
        record("subtitle:\(streamIndex)")
        return Data(srt.utf8)
    }

    func primaryImageURL(for item: BaseItem) -> URL? { nil }

    func reportStart(_ report: PlaybackReport) async throws { record("start:\(report.playSessionId ?? "-")") }
    func reportProgress(_ report: PlaybackReport) async throws {
        record("progress:\(report.playSessionId ?? "-"):\(report.isPaused ? "paused" : "playing")")
    }
    func reportStopped(_ report: PlaybackReport) async throws {
        record("stopped:\(report.playSessionId ?? "-"):\(Int(Ticks.seconds(report.positionTicks)))")
    }
    func endEncoding(playSessionId: String) async throws { record("endEncoding:\(playSessionId)") }
}

func movie(height: Int = 1080, resumeAt seconds: Double? = nil, defaultSubtitle: Int? = nil, defaultAudio: Int = 1) -> BaseItem {
    let json = """
    {"Id":"m1","Name":"Movie","Type":"Movie","RunTimeTicks":6000000000,
     "UserData":{"PlaybackPositionTicks":\(Int64((seconds ?? 0) * 10_000_000))},
     "MediaSources":[{"Id":"src","DefaultSubtitleStreamIndex":\(defaultSubtitle ?? -1),"DefaultAudioStreamIndex":\(defaultAudio),"MediaStreams":[
       {"Type":"Video","Index":0,"Codec":"hevc","Height":\(height)},
       {"Type":"Audio","Index":1,"Codec":"eac3"},
       {"Type":"Subtitle","Index":2,"Codec":"subrip","Language":"eng","DisplayTitle":"English","IsTextSubtitleStream":true},
       {"Type":"Subtitle","Index":3,"Codec":"PGSSUB","Language":"spa","DisplayTitle":"Spanish","IsTextSubtitleStream":false},
       {"Type":"Subtitle","Index":4,"Codec":"subrip","Language":"fra","DisplayTitle":"French","IsExternal":true,"IsTextSubtitleStream":true},
       {"Type":"Audio","Index":5,"Codec":"aac","Language":"spa","DisplayTitle":"Spanish"}
     ]}]}
    """
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .custom { path in
        let key = path.last!
        struct K: CodingKey { var stringValue: String; var intValue: Int?; init(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { nil } }
        return K(stringValue: key.stringValue.prefix(1).lowercased() + key.stringValue.dropFirst())
    }
    return try! decoder.decode(BaseItem.self, from: Data(json.utf8))
}

@MainActor
func eventually(_ timeout: TimeInterval = 3, _ condition: @escaping () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return condition()
}

/// An 8-bit 4:2:0 frame that is video black except for mid-grey picture rows between the bars.
func letterboxedFrame(width: Int, height: Int, top: Int, bottom: Int) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &buffer)
    let frame = buffer!
    CVPixelBufferLockBaseAddress(frame, [])
    let stride = CVPixelBufferGetBytesPerRowOfPlane(frame, 0)
    let luma = CVPixelBufferGetBaseAddressOfPlane(frame, 0)!.assumingMemoryBound(to: UInt8.self)
    for row in 0..<height {
        let value: UInt8 = row >= top && row < height - bottom ? 128 : 16
        for x in 0..<width { luma[row * stride + x] = value }
    }
    CVPixelBufferUnlockBaseAddress(frame, [])
    return frame
}

/// Canned library answers. `onItems` decides what any `/Items` query returns.
final class FakeLibraryService: LibraryService, @unchecked Sendable {
    let lock = NSLock()
    var libraryList: [BaseItem] = []
    var resume: [BaseItem] = []
    var nextUpItems: [BaseItem] = []
    var nextUpBySeries: [String: [BaseItem]] = [:]
    var latestItems: [BaseItem] = []
    var similarItems: [BaseItem] = []
    var genreList: [NameGuidPair] = []
    var seasonList: [BaseItem] = []
    var episodesBySeason: [String: [BaseItem]] = [:]
    var onItems: (ItemQuery) -> [BaseItem] = { _ in [] }
    var errors: Set<String> = []
    private(set) var queries: [ItemQuery] = []

    func libraries() async throws -> [BaseItem] { libraryList }
    func resumeItems() async throws -> [BaseItem] { try check("resume"); return resume }
    func nextUp(limit: Int, seriesId: String?) async throws -> [BaseItem] {
        try check("nextUp")
        if let seriesId { return nextUpBySeries[seriesId] ?? [] }
        return Array(nextUpItems.prefix(limit))
    }
    func latest(limit: Int) async throws -> [BaseItem] { try check("latest"); return Array(latestItems.prefix(limit)) }
    func items(_ query: ItemQuery) async throws -> ItemsResult {
        try check("items")
        lock.withLock { queries.append(query) }
        let all = onItems(query)
        let page = Array(all.dropFirst(query.startIndex).prefix(query.limit))
        return ItemsResult(items: page, totalRecordCount: all.count, startIndex: query.startIndex)
    }
    func similar(to itemId: String, limit: Int) async throws -> [BaseItem] { similarItems }
    func genres(libraryId: String?) async throws -> [NameGuidPair] { genreList }
    func seasons(seriesId: String) async throws -> [BaseItem] { try check("seasons"); return seasonList }
    func episodes(seriesId: String, seasonId: String) async throws -> [BaseItem] { episodesBySeason[seasonId] ?? [] }
    func item(id: String) async throws -> BaseItem { BaseItem(id: id) }
    func markPlayed(_ itemId: String, played: Bool) async throws -> UserItemData { UserItemData(played: played) }
    func primaryImageURL(for item: BaseItem, maxHeight: Int) -> URL? { nil }
    func backdropImageURL(for item: BaseItem, maxWidth: Int) -> URL? { nil }

    private func check(_ name: String) throws {
        if errors.contains(name) { throw JellyfinError.network("\(name) failed") }
    }
}

func item(_ id: String, type: ItemKind = .movie, minutes: Int? = nil, year: Int? = nil, created: String? = nil,
          unplayed: Int? = nil, lastPlayed: String? = nil, position: Double? = nil) -> BaseItem {
    var item = BaseItem(id: id, name: id.capitalized, type: type)
    item.runTimeTicks = minutes.map { Int64($0) * 60 * 10_000_000 }
    item.productionYear = year
    item.dateCreated = created
    if unplayed != nil || lastPlayed != nil || position != nil {
        item.userData = UserItemData(playbackPositionTicks: position.map { Int64($0 * 10_000_000) },
                                     unplayedItemCount: unplayed, lastPlayedDate: lastPlayed)
    }
    return item
}
