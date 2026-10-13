import JellyfinKit
import SwiftUI

/// The overlay a title opens into: poster, facts, overview, progress, Resume or Play, Start over,
/// Mark watched. ← → move along the row; Esc closes.
struct QuickLookView: View {
    @Environment(AppModel.self) private var model
    let item: BaseItem
    let onPlay: (BaseItem, Bool) -> Void
    let onOpenSeries: (BaseItem) -> Void
    let onUpdate: (BaseItem) -> Void
    let onClose: () -> Void
    @State private var details: BaseItem?
    @State private var marking = false
    @State private var markError: String?

    private var shown: BaseItem {
        var merged = details ?? item
        // The row's item carries fresher user data after Mark watched.
        if details != nil { merged.userData = item.userData ?? merged.userData }
        return merged
    }
    private var inProgress: Bool { shown.resumePositionSeconds != nil }
    private var playable: Bool { shown.type?.isPlayable ?? false }
    private var watched: Bool { shown.userData?.played == true }

    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            Artwork(url: model.client?.primaryImageURL(for: shown, maxHeight: 600), title: ItemLabels.title(shown), toneID: shown.id)
                .frame(width: 180, height: 270)
                .clipShape(RoundedRectangle(cornerRadius: BrowserStyle.corner))
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        if shown.type == .episode, let series = shown.seriesName {
                            Text(series).font(.system(size: 14, weight: .medium)).foregroundStyle(BrowserStyle.dim)
                        }
                        Text(shown.displayName)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(BrowserStyle.text)
                            .lineLimit(2)
                    }
                    Spacer()
                    HStack(spacing: 14) {
                        KeyHint(keys: ["←", "→"], text: "next title")
                        KeyHint(keys: ["esc"], text: "closes")
                    }
                }
                Text(facts).font(.system(size: 14)).foregroundStyle(BrowserStyle.dim)
                if let overview = shown.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .foregroundStyle(Color(red: 0xd6 / 255, green: 0xd2 / 255, blue: 0xcb / 255))
                        .lineLimit(5)
                        .frame(maxWidth: 560, alignment: .leading)
                } else if details == nil {
                    ProgressView().controlSize(.small)
                }
                if inProgress, let pct = shown.userData?.playedPercentage {
                    ProgressLine(fraction: pct / 100).clipShape(Capsule())
                    if let left = ItemLabels.timeLeft(shown) {
                        Text(left).font(.system(size: 13)).foregroundStyle(BrowserStyle.muted)
                    }
                }
                if let markError {
                    Text(markError).font(.system(size: 13)).foregroundStyle(.red)
                }
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    if playable {
                        ActionButton(title: inProgress ? "Resume" : "Play", icon: "play.fill", role: .primary) { onPlay(shown, inProgress) }
                        if inProgress { ActionButton(title: "Start over") { onPlay(shown, false) } }
                    } else {
                        ActionButton(title: "Open series", icon: "chevron.right", role: .primary) { onOpenSeries(shown) }
                    }
                    if playable {
                        ActionButton(title: watched ? "Mark unwatched" : "Mark watched") { Task { await mark(!watched) } }
                            .disabled(marking)
                    }
                    Spacer()
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(width: 820, height: 318)
        .background(BrowserStyle.raised, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(BrowserStyle.line))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 20)
        .task(id: item.id) {
            details = nil
            markError = nil
            guard let client = model.client else { return }
            details = try? await client.item(id: item.id)
        }
    }

    private var facts: String {
        var parts: [String] = []
        if shown.type == .episode {
            if let label = shown.episodeLabel { parts.append(label.replacingOccurrences(of: " · ", with: " ")) }
            if let date = shown.dateLabel { parts.append(date) }
        } else if let year = shown.productionYear {
            parts.append(String(year))
        }
        if let runtime = shown.runtimeMinutes, shown.type != .series { parts.append(ItemLabels.minutes(runtime)) }
        if let genres = shown.genres, !genres.isEmpty { parts.append(genres.prefix(2).joined(separator: ", ")) }
        parts += shown.formatBadges
        return parts.joined(separator: " · ")
    }

    private func mark(_ played: Bool) async {
        guard let client = model.client else { return }
        marking = true
        defer { marking = false }
        do {
            let data = try await client.markPlayed(shown.id, played: played)
            var updated = item
            updated.userData = data
            if !played { updated.userData?.playbackPositionTicks = 0 }
            onUpdate(updated)
            markError = nil
        } catch {
            markError = describe(error)
        }
    }
}
