import JellyfinKit
import SwiftUI

/// Artwork with a flat, titled placeholder when there is none or it fails to load.
struct Artwork: View {
    let url: URL?
    let title: String
    let toneID: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            BrowserStyle.placeholderTone(for: toneID)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BrowserStyle.text)
                .lineLimit(3)
                .padding(10)
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
            let art = shape == .poster
                ? model.client?.primaryImageURL(for: item, maxHeight: 450)
                : model.client?.backdropImageURL(for: item, maxWidth: 800) ?? model.client?.primaryImageURL(for: item, maxHeight: 450)
            Artwork(url: art, title: ItemLabels.title(item), toneID: item.id)
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
                    }
                }
            Text(ItemLabels.title(item))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(BrowserStyle.text)
                .lineLimit(1)
            Text(ItemLabels.detail(item))
                .font(.system(size: 12.5))
                .foregroundStyle(BrowserStyle.muted)
                .lineLimit(1)
        }
        .frame(width: size.width, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A one-click filter or genre.
struct Pill: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(on ? BrowserStyle.ground : BrowserStyle.dim)
                .padding(.horizontal, 13)
                .frame(height: 30)
                .background(on ? BrowserStyle.text : .clear, in: Capsule())
                .overlay(Capsule().stroke(on ? BrowserStyle.text : BrowserStyle.line))
        }
        .buttonStyle(.plain)
    }
}

/// The amber primary action and its quiet siblings.
struct ActionButton: View {
    enum Role { case primary, secondary }
    let title: String
    var icon: String? = nil
    var role: Role = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .bold)) }
                Text(title)
            }
            .font(.system(size: 15, weight: role == .primary ? .semibold : .regular))
            .foregroundStyle(role == .primary ? BrowserStyle.ground : BrowserStyle.text)
            .padding(.horizontal, role == .primary ? 22 : 18)
            .frame(height: 44)
            .background(role == .primary ? BrowserStyle.accent : .clear, in: Capsule())
            .overlay(Capsule().stroke(role == .primary ? .clear : .white.opacity(0.28)))
        }
        .buttonStyle(.plain)
    }
}
