#if canImport(AVFoundation)
import AVFoundation
import Foundation
import VideoToolbox

/// A stream to play: URL, request headers (Authorization), and the offset between the
/// stream's timestamps and the item timeline.
public struct MediaSource: Sendable, Equatable {
    public var url: URL
    public var headers: [String: String]
    public var timelineOffset: Double

    public init(url: URL, headers: [String: String] = [:], timelineOffset: Double = 0) {
        self.url = url
        self.headers = headers
        self.timelineOffset = timelineOffset
    }
}

public enum EngineState: Sendable, Equatable {
    case idle
    case loading
    case buffering
    case playing
    case paused
    case ended
    case failed(String)
}

public enum EngineEvent: Sendable {
    case state(EngineState)
    /// Playback position jumped (seek or switch) to the given time.
    case jumped(Double)
    /// A quality switch finished splicing in the new stream.
    case switched
}

public struct EngineError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// What this Mac can play locally.
public struct EngineCapabilities: Sendable, Equatable {
    public var av1: Bool
    public var hevc: Bool
    public var hdr: Bool
    public var dolbyVision: Bool

    public init(av1: Bool, hevc: Bool, hdr: Bool, dolbyVision: Bool) {
        self.av1 = av1
        self.hevc = hevc
        self.hdr = hdr
        self.dolbyVision = dolbyVision
    }

    public static func current() -> EngineCapabilities {
        let hdr = AVPlayer.eligibleForHDRPlayback
        return EngineCapabilities(av1: VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1),
                                  hevc: VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC),
                                  hdr: hdr, dolbyVision: hdr)
    }
}

/// The playback engine used by the app. All methods may be called from the main thread.
public protocol PlaybackEngine: AnyObject {
    var displayLayer: AVSampleBufferDisplayLayer { get }
    var state: EngineState { get }
    var currentTime: Double { get }
    var duration: Double? { get }
    var tracks: [MediaTrack] { get }
    var isPlaying: Bool { get }
    var volume: Float { get set }
    var isMuted: Bool { get set }
    var onEvent: (@MainActor (EngineEvent) -> Void)? { get set }

    /// Opens the source, positions it at `startAt` and buffers. Playback starts paused.
    func prepare(source: MediaSource, startAt: Double) async throws
    func play()
    func pause()
    func seek(to time: Double) async
    /// Opens `source` in the background while the current one keeps playing, then splices it in
    /// at a keyframe. Throws (and keeps the current stream) if the new one cannot be loaded.
    func switchSource(_ source: MediaSource, startAt: Double) async throws
    /// Shows cues from an embedded text track (nil hides embedded subtitles).
    func selectEmbeddedSubtitle(trackId: Int?)
    /// Shows externally loaded cues instead of an embedded track (nil clears them).
    func setExternalSubtitles(_ cues: [SubtitleCue]?)
    func subtitleText(at time: Double) -> String?
    func stop()
}
#endif
