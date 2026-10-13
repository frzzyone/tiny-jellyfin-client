import JellyfinKit
import SwiftUI

/// Artwork with a flat, titled placeholder when there is none or it fails to load.
struct Artwork: View {
    let url: URL?
    let title: String
    let toneID: String

    var body: some View {
        // The colour is flexible, so the frame decides the size and the image fills it; an image
        // laid out on its own would push the frame to its natural size.
        BrowserStyle.placeholderTone(for: toneID)
            .overlay(alignment: .bottomLeading) {
                Text(title)
                    .font(.system(size: BrowserStyle.cardTitleSize, weight: .semibold))
                    .foregroundStyle(BrowserStyle.text)
                    .lineLimit(3)
                    .padding(10)
            }
            .overlay {
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        }
                    }
                }
            }
            .clipped()
    }
}

/// The 4 pt progress line along the bottom of a card.
struct ProgressLine: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.18))
                Rectangle().fill(BrowserStyle.accent).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 4)
    }
}

/// A poster (2:3) or still (16:9) card with its two text lines. Selected cards are outlined.
struct ItemCard: View {
    @Environment(AppModel.self) private var model
    let item: BaseItem
    let shape: RowShape
    let selected: Bool
    var width: CGFloat? = nil
    /// On a series' own page: the episode's still and "2 · Title" instead of the series'.
    var inSeries = false
    @State private var hovering = false

    private var title: String {
        guard inSeries else { return ItemLabels.title(item) }
        return [item.indexNumber.map(String.init), item.displayName].compactMap { $0 }.joined(separator: " · ")
    }

    private var detail: String {
        guard inSeries else { return ItemLabels.detail(item) }
        return ItemLabels.timeLeft(item) ?? item.runtimeMinutes.map(ItemLabels.minutes) ?? ""
    }

    private var size: CGSize {
        let base = shape == .poster ? BrowserStyle.posterSize : BrowserStyle.stillSize
        guard let width else { return base }
        return CGSize(width: width, height: width * base.height / base.width)
    }

    private var fraction: Double? {
        guard let pct = item.userData?.playedPercentage, pct > 0, item.userData?.played != true else { return nil }
        return pct / 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let art = shape == .poster || inSeries
                ? model.client?.primaryImageURL(for: item, maxHeight: 450)
                : model.client?.backdropImageURL(for: item, maxWidth: 800) ?? model.client?.primaryImageURL(for: item, maxHeight: 450)
            Artwork(url: art, title: title, toneID: item.id)
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .bottom) { if let fraction { ProgressLine(fraction: fraction) } }
                .overlay(alignment: .topTrailing) {
                    if item.userData?.played == true {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(BrowserStyle.ground)
                            .frame(width: 18, height: 18)
                            .background(BrowserStyle.text, in: Circle())
                            .padding(8)
                            .accessibilityLabel("Watched")
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: BrowserStyle.corner))
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: BrowserStyle.corner + 3)
                            .stroke(BrowserStyle.text, lineWidth: 2)
                            .padding(-3)
                    } else if hovering {
                        RoundedRectangle(cornerRadius: BrowserStyle.corner)
                            .stroke(.white.opacity(0.45), lineWidth: 1.5)
                    }
                }
                .shadow(color: .black.opacity(hovering ? 0.5 : 0), radius: 12, y: 6)
                .scaleEffect(hovering ? 1.04 : 1)
                .animation(.easeOut(duration: 0.15), value: hovering)
            Text(title)
                .font(.system(size: BrowserStyle.cardTitleSize, weight: .medium))
                .foregroundStyle(BrowserStyle.text)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: BrowserStyle.cardDetailSize))
                .foregroundStyle(BrowserStyle.muted)
                .lineLimit(1)
        }
        .frame(width: size.width, alignment: .leading)
        .contentShape(Rectangle())
        .onPointerHover { over in
            hovering = over
            #if os(macOS)
            if over { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            #endif
        }
    }
}

/// A one-click filter or genre.
struct Pill: View {
    let title: String
    let on: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(on ? BrowserStyle.ground : (hovering ? BrowserStyle.text : BrowserStyle.dim))
                .padding(.horizontal, 13)
                .frame(height: 30)
                .background(on ? BrowserStyle.text : (hovering ? BrowserStyle.raised : .clear), in: Capsule())
                .overlay(Capsule().stroke(on ? BrowserStyle.text : BrowserStyle.line))
        }
        .buttonStyle(.plain)
        .onPointerHover { hovering = $0 }
    }
}

/// The amber primary action and its quiet siblings.
struct ActionButton: View {
    enum Role { case primary, secondary }
    let title: String
    var icon: String? = nil
    var role: Role = .secondary
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .bold)) }
                Text(title)
            }
            .font(.system(size: 15, weight: role == .primary ? .semibold : .regular))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(role == .primary ? BrowserStyle.ground : BrowserStyle.text)
            .padding(.horizontal, role == .primary ? 22 : 18)
            .frame(height: 44)
            .background(role == .primary ? BrowserStyle.accent : (hovering ? .white.opacity(0.08) : .clear), in: Capsule())
            .overlay(Capsule().stroke(role == .primary ? .clear : .white.opacity(hovering ? 0.5 : 0.28)))
            .brightness(role == .primary && hovering ? 0.06 : 0)
        }
        .buttonStyle(.plain)
        .onPointerHover { hovering = $0 }
    }
}

extension View {
    /// `onHover` where there is a pointer; the Apple TV has none (focus does the lifting there).
    func onPointerHover(perform action: @escaping (Bool) -> Void) -> some View {
        #if os(tvOS)
        self
        #else
        onHover(perform: action)
        #endif
    }

    /// A card that opens on a click rather than being a Button (a Button would take the
    /// double-click too): VoiceOver reads it as one button and can press it.
    func cardAccessibility(_ open: @escaping () -> Void) -> some View {
        accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, open)
    }
}
