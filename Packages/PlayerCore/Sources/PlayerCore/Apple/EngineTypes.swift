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

public struct EngineError: LocalizedError, CustomStringConvertible {
    public let description: String
    /// The stream was too slow, rather than broken: worth trying again another way.
    public let isTimeout: Bool
    public init(_ description: String, isTimeout: Bool = false) {
        self.description = description
        self.isTimeout = isTimeout
    }
    public var errorDescription: String? { description }
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

    /// What this Mac can *decode*. Deliberately not `AVPlayer.eligibleForHDRPlayback`: that
    /// describes the current display and changes with the window, which would make the server's
    /// direct-play decision flip between launches and force a full transcode of HDR and Dolby
    /// Vision files. Whether the panel can show the result is macOS's business — it tone-maps.
    public static func current() -> EngineCapabilities {
        let hevc = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        return EngineCapabilities(av1: VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1),
                                  hevc: hevc, hdr: hevc,
                                  dolbyVision: VTIsHardwareDecodeSupported(kCMVideoCodecType_DolbyVisionHEVC))
    }
}

/// The playback engine used by the app. All methods may be called from the main thread.
public protocol PlaybackEngine: AnyObject {
    var displayLayer: AVSampleBufferDisplayLayer { get }
    var state: EngineState { get }
    var currentTime: Double { get }
    var duration: Double? { get }
    /// Size the picture should be displayed at, once the stream is open.
    var videoSize: CGSize? { get }
    /// The video's format (codec, HDR10/HLG/Dolby Vision signalling) and frames per second, for
    /// switching the display to match. Nil until known, which for MPEG-TS is the first keyframe.
    var videoFormatDescription: CMVideoFormatDescription? { get }
    var frameRate: Double? { get }
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
    /// The frame on screen right now, for looking at its pixels (letterbox detection); nil when
    /// nothing is displayed or the renderer cannot hand it out.
    func copyDisplayedFrame() -> CVPixelBuffer?
    func stop()
    /// One-line internal state for diagnostics.
    var debugSummary: String { get }
}
#endif
