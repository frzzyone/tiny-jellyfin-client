import AppKit
import JellyfinKit
import SwiftUI

/// How subtitle text is drawn: a font, and its point size on a 1080-line picture. The drawn size
/// scales with the picture, so the same setting looks the same in a small window and full screen.
struct SubtitleStyle: Equatable {
    /// PostScript name; nil is the app's default (the system font, semibold).
    var fontName: String?
    var size: Double = SubtitleStyle.defaultSize

    static let defaultSize: Double = 48
    static let referenceHeight: Double = 1080
    static let minimumPointSize: Double = 12
    static let `default` = SubtitleStyle()

    var isDefault: Bool { self == .default }

    /// The font as the Font panel should show it: at the reference size.
    var referenceFont: NSFont { font(pointSize: size) }

    /// The font to draw with on a picture of the given height.
    func font(forPictureHeight height: CGFloat) -> NSFont {
        font(pointSize: max(Self.minimumPointSize, size * Double(height) / Self.referenceHeight))
    }

    /// "Helvetica Bold 48", or "System 48" for the default.
    var label: String {
        let name = fontName.flatMap { NSFont(name: $0, size: size)?.displayName } ?? "System"
        return "\(name) \(Int(size.rounded()))"
    }

    private func font(pointSize: Double) -> NSFont {
        // A font that is no longer installed falls back to the default rather than to nothing.
        if let fontName, let font = NSFont(name: fontName, size: pointSize) { return font }
        return .systemFont(ofSize: pointSize, weight: .semibold)
    }
}

extension SubtitleStyle {
    init(_ preferences: AppPreferences) {
        self.init(fontName: preferences.subtitleFontName, size: preferences.subtitleFontSize ?? Self.defaultSize)
    }

    func save(to preferences: AppPreferences) {
        preferences.subtitleFontName = fontName
        preferences.subtitleFontSize = isDefault ? nil : size
    }
}

enum SubtitleLayout {
    /// Where the picture is inside the player view: aspect-fitted and centred, as the display layer
    /// draws it. The whole view when the video size is not known yet.
    static func pictureRect(video: CGSize?, in bounds: CGSize) -> CGRect {
        let whole = CGRect(origin: .zero, size: bounds)
        guard let video, video.width > 0, video.height > 0, bounds.width > 0, bounds.height > 0 else { return whole }
        let scale = min(bounds.width / video.width, bounds.height / video.height)
        let size = CGSize(width: video.width * scale, height: video.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}

/// The standard Font panel, reporting the user's picks. The panel sends `changeFont:` to the font
/// manager's target; colour and underline (`changeAttributes:`) are not handled, so they do nothing.
@MainActor
final class SubtitleFontPanel: NSObject {
    static let shared = SubtitleFontPanel()

    private var current = NSFont.systemFont(ofSize: 48)
    private var onChange: ((NSFont) -> Void)?

    func show(current: NSFont, onChange: @escaping (NSFont) -> Void) {
        self.current = current
        self.onChange = onChange
        let manager = NSFontManager.shared
        manager.target = self
        manager.setSelectedFont(current, isMultiple: false)
        manager.orderFrontFontPanel(nil)
    }

    @objc func changeFont(_ sender: Any?) {
        current = NSFontManager.shared.convert(current)
        onChange?(current)
    }
}
