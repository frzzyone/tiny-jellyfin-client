import Foundation

/// A streaming quality choice. `original` has no caps; presets cap bitrate and vertical resolution.
public struct QualityPreset: Hashable, Sendable, Identifiable {
    public let id: String
    public let label: String
    /// Bits per second, nil for Original.
    public let maxBitrate: Int?
    /// Pixels, nil for Original.
    public let maxHeight: Int?

    public var isOriginal: Bool { maxBitrate == nil }

    public static let original = QualityPreset(id: "original", label: "Original", maxBitrate: nil, maxHeight: nil)

    /// Fixed presets, highest first.
    public static let presets: [QualityPreset] = [
        QualityPreset(id: "2160p-40", label: "4K 40 Mbps", maxBitrate: 40_000_000, maxHeight: 2160),
        QualityPreset(id: "1080p-20", label: "1080p 20 Mbps", maxBitrate: 20_000_000, maxHeight: 1080),
        QualityPreset(id: "1080p-10", label: "1080p 10 Mbps", maxBitrate: 10_000_000, maxHeight: 1080),
        QualityPreset(id: "720p-4", label: "720p 4 Mbps", maxBitrate: 4_000_000, maxHeight: 720),
        QualityPreset(id: "480p-1.5", label: "480p 1.5 Mbps", maxBitrate: 1_500_000, maxHeight: 480),
        QualityPreset(id: "360p-0.72", label: "360p 720 kbps", maxBitrate: 720_000, maxHeight: 360),
    ]

    public static let all: [QualityPreset] = [original] + presets

    public static func with(id: String) -> QualityPreset? { all.first { $0.id == id } }

    /// Bitrate sent as MaxStreamingBitrate for Original: effectively uncapped.
    public static let originalMaxStreamingBitrate = 200_000_000

    public var maxStreamingBitrate: Int { maxBitrate ?? Self.originalMaxStreamingBitrate }
}

public enum QualitySelection {
    /// Options offered for a source: Original plus every preset whose height does not exceed
    /// the source's. Unknown source height shows everything.
    public static func visibleOptions(sourceHeight: Int?) -> [QualityPreset] {
        guard let sourceHeight, sourceHeight > 0 else { return QualityPreset.all }
        // Allow small deviations (e.g. 1080p encoded as 1072 or 1088 lines, cropped 4K at 1600).
        let effective = Self.nominalHeight(sourceHeight)
        return [.original] + QualityPreset.presets.filter { ($0.maxHeight ?? 0) <= effective }
    }

    /// Maps a coded/cropped height to the nominal resolution class it belongs to.
    static func nominalHeight(_ height: Int) -> Int {
        switch height {
        case 1500...: return 2160
        case 900...: return 1080
        case 600...: return 720
        case 420...: return 480
        default: return 360
        }
    }

    /// Starting quality for a playback: the remembered preference when it is offered for this
    /// source, otherwise Original. The stored preference itself is never changed here.
    public static func startingQuality(preferredId: String?, sourceHeight: Int?) -> QualityPreset {
        guard let preferredId, let preferred = QualityPreset.with(id: preferredId) else { return .original }
        return visibleOptions(sourceHeight: sourceHeight).contains(preferred) ? preferred : .original
    }
}
