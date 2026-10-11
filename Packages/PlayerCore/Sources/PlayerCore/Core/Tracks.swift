import Foundation

public enum TrackKind: String, Sendable, Equatable {
    case video, audio, subtitle, other
}

/// A stream inside the media, as shown in menus.
public struct MediaTrack: Sendable, Equatable, Identifiable {
    /// The stream index inside the container.
    public let id: Int
    public let kind: TrackKind
    public let codec: String
    public let language: String?
    public let title: String?
    public let isDefault: Bool
    public let isForced: Bool

    public static let textSubtitleCodecs: Set<String> = ["subrip", "srt", "ass", "ssa", "webvtt", "mov_text", "text"]

    public var isTextSubtitle: Bool { kind == .subtitle && Self.textSubtitleCodecs.contains(codec) }

    public var displayName: String {
        let parts = [language.map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }, title]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "Track \(id)" : parts.joined(separator: " — ")
    }
}

/// HDR-related colour description of a video stream.
public struct VideoColorInfo: Sendable, Equatable {
    public enum Transfer: Sendable, Equatable { case sdr, pq, hlg }
    public var primaries: Int32 = 0
    public var transfer: Int32 = 0
    public var matrix: Int32 = 0
    public var fullRange = false
    /// SMPTE ST 2086 mastering display, as the 24-byte 'mdcv' payload.
    public var masteringDisplay: Data?
    /// Content light level, as the 4-byte 'clli' payload.
    public var contentLightLevel: Data?

    public var transferKind: Transfer {
        switch transfer {
        case 16: return .pq      // AVCOL_TRC_SMPTE2084
        case 18: return .hlg     // AVCOL_TRC_ARIB_STD_B67
        default: return .sdr
        }
    }
}

/// Dolby Vision decoder configuration (from the dvcC/dvvC record).
public struct DolbyVisionConfig: Sendable, Equatable {
    public var versionMajor: UInt8
    public var versionMinor: UInt8
    public var profile: UInt8
    public var level: UInt8
    public var rpuPresent: Bool
    public var elPresent: Bool
    public var blPresent: Bool
    public var blSignalCompatibilityId: UInt8

    /// The 24-byte dvcC/dvvC box payload.
    public var boxPayload: Data {
        var bytes = [UInt8](repeating: 0, count: 24)
        bytes[0] = versionMajor
        bytes[1] = versionMinor
        // dv_profile(7) dv_level(6) rpu(1) el(1) bl(1)
        let packed: UInt16 = (UInt16(profile & 0x7F) << 9) | (UInt16(level & 0x3F) << 3)
            | (rpuPresent ? 4 : 0) | (elPresent ? 2 : 0) | (blPresent ? 1 : 0)
        bytes[2] = UInt8(packed >> 8)
        bytes[3] = UInt8(packed & 0xFF)
        bytes[4] = (blSignalCompatibilityId & 0x0F) << 4
        return Data(bytes)
    }

    /// Atom name for the record: dvcC up to profile 7, dvvC from profile 8.
    public var boxType: String { profile <= 7 ? "dvcC" : "dvvC" }
}
