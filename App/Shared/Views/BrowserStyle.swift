import SwiftUI

/// The browser's look: graphite and off-white chrome, posters as the only colour, one amber accent
/// spent on progress and Play. The player window keeps its own black.
enum BrowserStyle {
    static let ground = Color(red: 0x1b / 255, green: 0x1f / 255, blue: 0x26 / 255)
    static let card = Color(red: 0x2a / 255, green: 0x2f / 255, blue: 0x38 / 255)
    static let raised = Color(red: 0x26 / 255, green: 0x2b / 255, blue: 0x34 / 255)
    static let line = Color(red: 0x2f / 255, green: 0x35 / 255, blue: 0x3f / 255)
    static let text = Color(red: 0xed / 255, green: 0xe9 / 255, blue: 0xe3 / 255)
    static let muted = Color(red: 0x8e / 255, green: 0x96 / 255, blue: 0xa3 / 255)
    static let dim = Color(red: 0xb7 / 255, green: 0xbd / 255, blue: 0xc7 / 255)
    static let accent = Color(red: 0xf5 / 255, green: 0xc4 / 255, blue: 0x51 / 255)

    static let posterSize = CGSize(width: 150, height: 225)
    static let stillSize = CGSize(width: 264, height: 148)
    static let sidePadding: CGFloat = 40
    static let rowGap: CGFloat = 14
    static let corner: CGFloat = 6
    #if os(tvOS)
    static let cardTitleSize: CGFloat = 23
    static let cardDetailSize: CGFloat = 19
    #else
    static let cardTitleSize: CGFloat = 14
    static let cardDetailSize: CGFloat = 12.5
    #endif

    /// Muted tones for posters without artwork, picked by the item's id so the same item always
    /// gets the same one.
    static func placeholderTone(for id: String) -> Color {
        let tones: [Color] = [
            Color(red: 0x3a / 255, green: 0x2f / 255, blue: 0x2a / 255), Color(red: 0x2a / 255, green: 0x35 / 255, blue: 0x40 / 255),
            Color(red: 0x34 / 255, green: 0x32 / 255, blue: 0x39 / 255), Color(red: 0x2d / 255, green: 0x3a / 255, blue: 0x33 / 255),
            Color(red: 0x3b / 255, green: 0x33 / 255, blue: 0x30 / 255), Color(red: 0x2f / 255, green: 0x33 / 255, blue: 0x38 / 255),
            Color(red: 0x35 / 255, green: 0x30 / 255, blue: 0x3a / 255),
        ]
        let hash = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fff_ffff }
        return tones[hash % tones.count]
    }
}

struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .scaledFont(size: 11.5)
            .foregroundStyle(BrowserStyle.dim)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .frame(minWidth: 20)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(BrowserStyle.line))
    }
}

/// "↑ ↓ rows" and friends, at the foot of a page.
struct KeyHint: View {
    let keys: [String]
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { KeyCap(label: $0) }
            Text(text).padding(.leading, 2)
        }
        .scaledFont(size: 13)
        .foregroundStyle(BrowserStyle.muted)
    }
}

extension View {
    /// A system font of `size` points at the default text size that grows and shrinks with the
    /// reader's Dynamic Type setting, like the text style nearest that size. The Mac has no Dynamic
    /// Type, so there it stays at `size`.
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }
}

struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: Self.style(for: size))
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }

    /// The text style whose default size (on iPhone) is nearest `size`, so it scales on that curve.
    static func style(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: .caption2
        case ..<12.5: .caption
        case ..<14: .footnote
        case ..<15.5: .subheadline
        case ..<16.5: .callout
        case ..<18.5: .body
        case ..<21: .title3
        case ..<25: .title2
        case ..<31: .title
        default: .largeTitle
        }
    }
}
