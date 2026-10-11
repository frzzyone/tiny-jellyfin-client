import Foundation

/// Jellyfin positions are in ticks: 1 tick = 100 ns, 10,000,000 ticks per second.
public enum Ticks {
    public static let perSecond: Int64 = 10_000_000

    public static func from(seconds: Double) -> Int64 {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int64((seconds * Double(perSecond)).rounded())
    }

    public static func seconds(_ ticks: Int64) -> Double {
        Double(ticks) / Double(perSecond)
    }
}

public enum TimeFormat {
    /// "42:10" or "1:02:30".
    public static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds : 0))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "1h 52m" / "48m" runtime label.
    public static func runtime(ticks: Int64) -> String {
        let minutes = Int((Ticks.seconds(ticks) / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
