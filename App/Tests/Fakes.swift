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

    func switchSource(_ source: MediaSource, startAt: Double) async throws {
        switches.append((source, startAt))
        if switchDelay > 0 { try await Task.sleep(nanoseconds: UInt64(switchDelay * 1_000_000_000)) }
        if let switchError { throw switchError }
    }

    func selectEmbeddedSubtitle(trackId: Int?) { embeddedSubtitle = trackId }
    func setExternalSubtitles(_ cues: [SubtitleCue]?) { externalCues = cues }
    func subtitleText(at time: Double) -> String? { nil }
    func stop() { stopped = true; state = .idle }

    @MainActor func send(_ event: EngineEvent) { onEvent?(event) }
}

final class FakeService: PlaybackService, @unchecked Sendable {
    let lock = NSLock()
    var streamHeaders: [String: String] = ["Authorization": "MediaBrowser Token=\"t\""]
    var serverURL = URL(string: "https://jf.test")!
    var item: BaseItem
    var resolveCalls: [(quality: QualityPreset, start: Double, subtitle: Int?)] = []
    var nextMethod: PlayMethod = .directPlay
    var resolveError: Error?
    var srt = "1\n00:00:01,000 --> 00:00:02,000\nServer cue\n"
    private(set) var events: [String] = []
    private var counter = 0

    init(item: BaseItem) { self.item = item }

    func record(_ event: String) { lock.lock(); events.append(event); lock.unlock() }
    var recorded: [String] { lock.lock(); defer { lock.unlock() }; return events }

    func item(id: String) async throws -> BaseItem { item }

    func resolveStream(itemId: String, quality: QualityPreset, capabilities: PlaybackCapabilities, startSeconds: Double,
                       mediaSourceId: String?, subtitleStreamIndex: Int?) async throws -> ResolvedStream {
        lock.lock()
        resolveCalls.append((quality, startSeconds, subtitleStreamIndex))
        counter += 1
        let n = counter
        lock.unlock()
        if let resolveError { throw resolveError }
        let method: PlayMethod = subtitleStreamIndex != nil ? .transcode : (quality.isOriginal ? nextMethod : .transcode)
        return ResolvedStream(url: URL(string: "https://jf.test/stream\(n)")!, playMethod: method,
                              mediaSource: item.mediaSources![0], mediaSourceId: "src",
                              playSessionId: "ps\(n)", timelineOffset: 0)
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

func movie(height: Int = 1080, resumeAt seconds: Double? = nil, defaultSubtitle: Int? = nil) -> BaseItem {
    let json = """
    {"Id":"m1","Name":"Movie","Type":"Movie","RunTimeTicks":6000000000,
     "UserData":{"PlaybackPositionTicks":\(Int64((seconds ?? 0) * 10_000_000))},
     "MediaSources":[{"Id":"src","DefaultSubtitleStreamIndex":\(defaultSubtitle ?? -1),"MediaStreams":[
       {"Type":"Video","Index":0,"Codec":"hevc","Height":\(height)},
       {"Type":"Audio","Index":1,"Codec":"eac3"},
       {"Type":"Subtitle","Index":2,"Codec":"subrip","Language":"eng","DisplayTitle":"English","IsTextSubtitleStream":true},
       {"Type":"Subtitle","Index":3,"Codec":"PGSSUB","Language":"spa","DisplayTitle":"Spanish","IsTextSubtitleStream":false},
       {"Type":"Subtitle","Index":4,"Codec":"subrip","Language":"fra","DisplayTitle":"French","IsExternal":true,"IsTextSubtitleStream":true}
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
