import Foundation

public struct PlaybackInfoRequest: Codable, Sendable, Equatable {
    public var userId: String
    public var maxStreamingBitrate: Int
    public var startTimeTicks: Int64
    public var mediaSourceId: String?
    public var audioStreamIndex: Int?
    public var subtitleStreamIndex: Int?
    public var enableDirectPlay: Bool
    public var enableDirectStream: Bool
    public var enableTranscoding: Bool
    public var allowVideoStreamCopy: Bool
    public var allowAudioStreamCopy: Bool
    public var autoOpenLiveStream: Bool
    public var alwaysBurnInSubtitleWhenTranscoding: Bool
    public var deviceProfile: DeviceProfile
}

/// How the stream reaches the player.
public enum PlayMethod: String, Sendable, Equatable {
    /// The file as-is.
    case directPlay = "DirectPlay"
    /// Video unchanged; container/audio converted by the server.
    case directStream = "DirectStream"
    /// Video re-encoded by the server.
    case transcode = "Transcode"

    public var label: String {
        switch self {
        case .directPlay: return "Direct Play"
        case .directStream: return "Direct Stream"
        case .transcode: return "Transcode"
        }
    }
}

/// A resolved, playable stream for one playback session.
public struct ResolvedStream: Sendable, Equatable {
    public var url: URL
    public var playMethod: PlayMethod
    public var mediaSource: MediaSourceInfo
    public var mediaSourceId: String
    public var playSessionId: String?
    /// Seconds the stream's own timeline is offset from the item timeline (non-zero when the
    /// server starts a transcode part-way into the item).
    public var timelineOffset: Double
}

public enum PlayMethodClassifier {
    /// TranscodeReasons that mean the video itself is re-encoded.
    static let videoReasons: Set<String> = [
        "VideoCodecNotSupported", "VideoProfileNotSupported", "VideoLevelNotSupported",
        "VideoResolutionNotSupported", "VideoBitDepthNotSupported", "VideoFramerateNotSupported",
        "VideoBitrateNotSupported", "VideoRangeTypeNotSupported", "VideoCodecTagNotSupported",
        "RefFramesNotSupported", "AnamorphicVideoNotSupported", "InterlacedVideoNotSupported",
        "ContainerBitrateExceedsLimit", "SubtitleCodecNotSupported", "DirectPlayError",
        "UnknownVideoStreamInfo",
    ]

    /// Classifies a server transcoding URL: Direct Stream when none of its TranscodeReasons
    /// touch the video, otherwise Transcode.
    public static func classify(transcodingUrl: String) -> PlayMethod {
        guard let components = URLComponents(string: transcodingUrl) else { return .transcode }
        let items = components.queryItems ?? []
        if let reasons = items.first(where: { $0.name.caseInsensitiveCompare("TranscodeReasons") == .orderedSame })?.value {
            let list = reasons.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return list.contains(where: videoReasons.contains) ? .transcode : .directStream
        }
        // No reasons listed: fall back to whether the video codec is copied.
        if let codec = items.first(where: { $0.name.caseInsensitiveCompare("VideoCodec") == .orderedSame })?.value,
           codec.lowercased() == "copy" {
            return .directStream
        }
        return .transcode
    }
}

extension JellyfinClient {
    public func playbackInfo(itemId: String, quality: QualityPreset, capabilities: PlaybackCapabilities,
                             startSeconds: Double, mediaSourceId: String?, subtitleStreamIndex: Int?) async throws
        -> PlaybackInfoResponse {
        let body = PlaybackInfoRequest(
            userId: try requireUserId(),
            maxStreamingBitrate: quality.maxStreamingBitrate,
            startTimeTicks: Ticks.from(seconds: startSeconds),
            mediaSourceId: mediaSourceId,
            audioStreamIndex: nil,
            subtitleStreamIndex: subtitleStreamIndex,
            enableDirectPlay: true,
            enableDirectStream: true,
            enableTranscoding: true,
            allowVideoStreamCopy: true,
            allowAudioStreamCopy: true,
            autoOpenLiveStream: true,
            alwaysBurnInSubtitleWhenTranscoding: false,
            deviceProfile: DeviceProfileBuilder.build(capabilities: capabilities, quality: quality)
        )
        return try await post("/Items/\(itemId)/PlaybackInfo", query: ["userId": try requireUserId()], body: body)
    }

    /// Picks the media source and URL the server chose. Throws `noPlayableStream` when the
    /// server offers neither direct play nor a transcoding URL.
    public func resolveStream(itemId: String, response: PlaybackInfoResponse, startSeconds: Double) throws
        -> ResolvedStream {
        if let code = response.errorCode, !code.isEmpty { throw JellyfinError.noPlayableStream(code) }
        guard let source = response.mediaSources.first(where: { $0.supportsDirectPlay == true || $0.transcodingUrl != nil })
            ?? response.mediaSources.first else {
            throw JellyfinError.noPlayableStream(nil)
        }
        let sourceId = source.id ?? itemId
        if source.supportsDirectPlay == true {
            let url = self.url("/Videos/\(itemId)/stream", query: [
                "static": "true", "mediaSourceId": sourceId, "playSessionId": response.playSessionId,
            ])
            return ResolvedStream(url: url, playMethod: .directPlay, mediaSource: source, mediaSourceId: sourceId,
                                  playSessionId: response.playSessionId, timelineOffset: 0)
        }
        guard let transcodingUrl = source.transcodingUrl, let url = resolve(serverRelative: transcodingUrl) else {
            throw JellyfinError.noPlayableStream(nil)
        }
        // Jellyfin HLS playlists cover the whole item from 0, so the stream timeline matches
        // the item timeline; progressive transcodes started at StartTimeTicks would not.
        let isHLS = transcodingUrl.contains(".m3u8")
        return ResolvedStream(url: url, playMethod: PlayMethodClassifier.classify(transcodingUrl: transcodingUrl),
                              mediaSource: source, mediaSourceId: sourceId, playSessionId: response.playSessionId,
                              timelineOffset: isHLS ? 0 : startSeconds)
    }

    /// URL for an external (sidecar) text subtitle, converted by the server to SRT.
    public func externalSubtitleURL(itemId: String, mediaSourceId: String, streamIndex: Int) -> URL {
        url("/Videos/\(itemId)/\(mediaSourceId)/Subtitles/\(streamIndex)/0/Stream.srt")
    }
}

public enum SubtitleSelection {
    /// The track to select when playback starts: the server's recommendation for the user's
    /// preferences (`DefaultSubtitleStreamIndex`), or nil (Off) when it recommends none.
    public static func defaultTrack(for source: MediaSourceInfo) -> MediaStream? {
        guard let index = source.defaultSubtitleStreamIndex, index >= 0 else { return nil }
        return source.subtitleStreams.first { $0.index == index }
    }
}
