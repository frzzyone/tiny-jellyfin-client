import Foundation

/// What the local playback engine can handle. Produced by PlayerCore at runtime and mapped by the app.
public struct PlaybackCapabilities: Sendable, Equatable {
    public var av1: Bool
    public var hevc10Bit: Bool
    public var dolbyVision: Bool
    public var maxHevcLevel: Int
    public var maxH264Level: Int

    public init(av1: Bool, hevc10Bit: Bool = true, dolbyVision: Bool = true, maxHevcLevel: Int = 183,
                maxH264Level: Int = 52) {
        self.av1 = av1
        self.hevc10Bit = hevc10Bit
        self.dolbyVision = dolbyVision
        self.maxHevcLevel = maxHevcLevel
        self.maxH264Level = maxH264Level
    }
}

// MARK: Jellyfin DeviceProfile wire model (subset)

public struct DeviceProfile: Codable, Sendable, Equatable {
    public var name: String
    public var maxStreamingBitrate: Int
    public var maxStaticBitrate: Int
    public var musicStreamingTranscodingBitrate: Int
    public var directPlayProfiles: [DirectPlayProfile]
    public var transcodingProfiles: [TranscodingProfile]
    public var containerProfiles: [ContainerProfile]
    public var codecProfiles: [CodecProfile]
    public var subtitleProfiles: [SubtitleProfile]
}

public struct DirectPlayProfile: Codable, Sendable, Equatable {
    public var container: String
    public var audioCodec: String?
    public var videoCodec: String?
    public var type: String
}

public struct TranscodingProfile: Codable, Sendable, Equatable {
    public var container: String
    public var type: String
    public var videoCodec: String
    public var audioCodec: String
    public var `protocol`: String
    public var context: String
    public var maxAudioChannels: String
    public var minSegments: Int
    public var breakOnNonKeyFrames: Bool
}

public struct ContainerProfile: Codable, Sendable, Equatable {
    public var type: String
    public var container: String
    public var conditions: [ProfileCondition]
}

public struct CodecProfile: Codable, Sendable, Equatable {
    public var type: String
    public var codec: String?
    public var conditions: [ProfileCondition]
}

public struct ProfileCondition: Codable, Sendable, Equatable {
    public var condition: String
    public var property: String
    public var value: String
    public var isRequired: Bool

    public static func lessThanEqual(_ property: String, _ value: Int, required: Bool = true) -> ProfileCondition {
        ProfileCondition(condition: "LessThanEqual", property: property, value: String(value), isRequired: required)
    }

    public static func equalsAny(_ property: String, _ values: [String], required: Bool = true) -> ProfileCondition {
        ProfileCondition(condition: "EqualsAny", property: property, value: values.joined(separator: "|"),
                         isRequired: required)
    }
}

public struct SubtitleProfile: Codable, Sendable, Equatable {
    public var format: String
    public var method: String
}

// MARK: Builder

public enum DeviceProfileBuilder {
    public static let directPlayContainers = "mkv,webm,mp4,m4v,mov,ts,mpegts"
    public static let audioCodecs = [
        "aac", "mp3", "ac3", "eac3", "flac", "alac", "opus", "vorbis", "dts", "truehd", "mlp",
        "pcm_s16le", "pcm_s24le", "pcm_s32le", "pcm_f32le", "pcm_s16be", "pcm_s24be",
    ]
    public static let textSubtitleFormats = ["srt", "subrip", "ass", "ssa", "vtt", "webvtt", "mov_text"]
    public static let imageSubtitleFormats = ["pgssub", "dvdsub", "dvbsub", "pgs", "vobsub"]

    public static func videoCodecs(_ caps: PlaybackCapabilities) -> [String] {
        caps.av1 ? ["h264", "hevc", "av1"] : ["h264", "hevc"]
    }

    /// Builds the profile for a quality choice. Presets add resolution caps so the server
    /// downscales instead of only lowering bitrate.
    public static func build(capabilities caps: PlaybackCapabilities, quality: QualityPreset) -> DeviceProfile {
        let video = videoCodecs(caps).joined(separator: ",")
        let audio = audioCodecs.joined(separator: ",")

        var codecProfiles: [CodecProfile] = [
            CodecProfile(type: "Video", codec: "h264", conditions: [
                .lessThanEqual("VideoLevel", caps.maxH264Level),
                .lessThanEqual("VideoBitDepth", 8),
            ]),
            CodecProfile(type: "Video", codec: "hevc", conditions: [
                .lessThanEqual("VideoLevel", caps.maxHevcLevel),
                .lessThanEqual("VideoBitDepth", caps.hevc10Bit ? 10 : 8),
                .equalsAny("VideoRangeType", hevcRangeTypes(caps), required: false),
            ]),
        ]
        if let maxHeight = quality.maxHeight {
            let maxWidth = Int((Double(maxHeight) * 16.0 / 9.0).rounded())
            codecProfiles.append(CodecProfile(type: "Video", codec: nil, conditions: [
                .lessThanEqual("Height", maxHeight),
                .lessThanEqual("Width", maxWidth),
            ]))
        }

        return DeviceProfile(
            name: JellyfinKitInfo.clientName,
            maxStreamingBitrate: quality.maxStreamingBitrate,
            maxStaticBitrate: quality.maxStreamingBitrate,
            musicStreamingTranscodingBitrate: 384_000,
            directPlayProfiles: [
                DirectPlayProfile(container: directPlayContainers, audioCodec: audio, videoCodec: video, type: "Video"),
            ],
            transcodingProfiles: [
                TranscodingProfile(container: "mp4", type: "Video", videoCodec: "hevc,h264", audioCodec: "aac,ac3,eac3",
                                   protocol: "hls", context: "Streaming", maxAudioChannels: "8",
                                   minSegments: 1, breakOnNonKeyFrames: false),
            ],
            containerProfiles: [],
            codecProfiles: codecProfiles,
            subtitleProfiles: textSubtitleFormats.flatMap {
                [SubtitleProfile(format: $0, method: "Embed"), SubtitleProfile(format: $0, method: "External")]
            } + imageSubtitleFormats.map { SubtitleProfile(format: $0, method: "Encode") }
        )
    }

    static func hevcRangeTypes(_ caps: PlaybackCapabilities) -> [String] {
        var types = ["SDR", "HDR10", "HLG", "HDR10Plus"]
        if caps.dolbyVision {
            types += ["DOVI", "DOVIWithHDR10", "DOVIWithHLG", "DOVIWithSDR"]
        }
        return types
    }
}
