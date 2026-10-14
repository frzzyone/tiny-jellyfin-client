import JellyfinKit
import SwiftUI

/// What a title opens into on the phone: backdrop and poster, facts, progress, Resume or Play,
/// Start over, Mark watched, overview. A series offers Open series instead.
struct PhoneDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(BrowserModel.self) private var browser
    @Environment(\.dismiss) private var dismiss
    let item: BaseItem
    let onPlay: (BaseItem, Bool) -> Void
    let onUpdate: (BaseItem) -> Void
    @State private var details: BaseItem?
    @State private var marking = false
    @State private var markError: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var shown: BaseItem {
        var merged = details ?? item
        if details != nil { merged.userData = item.userData ?? merged.userData }
        return merged
    }
    private var inProgress: Bool { shown.resumePositionSeconds != nil }
    private var playable: Bool { shown.type?.isPlayable ?? false }
    private var watched: Bool { shown.userData?.played == true }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    VStack(alignment: .leading, spacing: 14) {
                        if inProgress, let pct = shown.userData?.playedPercentage {
                            VStack(alignment: .leading, spacing: 6) {
                                ProgressLine(fraction: pct / 100).clipShape(Capsule())
                                if let left = ItemLabels.timeLeft(shown) {
                                    Text(left).scaledFont(size: 12.5).foregroundStyle(BrowserStyle.muted)
                                }
                            }
                        }
                        actions
                        if let markError {
                            Text(markError).scaledFont(size: 13).foregroundStyle(.red)
                        }
                        if let overview = shown.overview, !overview.isEmpty {
                            Text(overview).scaledFont(size: 15).lineSpacing(3)
                                .foregroundStyle(Color(red: 0xd6 / 255, green: 0xd2 / 255, blue: 0xcb / 255))
                        } else if details == nil {
                            ProgressView()
                        }
                    }
                    .padding(.horizontal, PhoneStyle.side)
                }
                .padding(.bottom, 24)
            }
            .background(BrowserStyle.raised)
            // Open series, then a season from it.
            .navigationDestination(for: BaseItem.self) { item in
                Group {
                    if item.type == .season { SeasonView(season: item) } else { SeriesView(series: item) }
                }
                .background(BrowserStyle.ground)
            }
        }
        // Swipe sideways for the neighbouring title in the row the sheet was opened from.
        .gesture(DragGesture(minimumDistance: 40).onEnded { drag in
            guard abs(drag.translation.width) > abs(drag.translation.height) * 1.5 else { return }
            browser.stepQuickLook(forward: drag.translation.width < 0)
        })
        .task(id: item.id) {
            details = nil
            markError = nil
            guard let client = model.client else { return }
            details = try? await client.item(id: item.id)
        }
    }

    private var header: some View {
        // The facts beside the poster, or under it when the text is too big to share the width.
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                                      : AnyLayout(HStackLayout(alignment: .bottom, spacing: 14))) {
            Artwork(url: model.client?.primaryImageURL(for: shown, maxHeight: 300), title: ItemLabels.title(shown), toneID: shown.id)
                .frame(width: 84, height: 126)
                .clipShape(RoundedRectangle(cornerRadius: BrowserStyle.corner))
            VStack(alignment: .leading, spacing: 4) {
                if shown.type == .episode, let series = shown.seriesName {
                    Text(series).scaledFont(size: 13, weight: .medium).foregroundStyle(BrowserStyle.dim)
                }
                Text(shown.displayName).scaledFont(size: 24, weight: .bold).foregroundStyle(BrowserStyle.text)
                Text(ItemLabels.facts(shown)).scaledFont(size: 13).foregroundStyle(BrowserStyle.dim).lineLimit(2)
                if !shown.formatBadges.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(shown.formatBadges, id: \.self) { badge in
                            Text(badge).scaledFont(size: 11, weight: .semibold).foregroundStyle(BrowserStyle.dim)
                                .lineLimit(1).fixedSize()
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(BrowserStyle.line))
                        }
                    }
                }
            }
            .padding(.bottom, 4)
        }
        .padding(.horizontal, PhoneStyle.side)
        // At least the backdrop's height; taller when the text needs it, with the backdrop behind.
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .bottomLeading)
        .background {
            ZStack {
                Artwork(url: model.client?.backdropImageURL(for: shown, maxWidth: 1000), title: "", toneID: shown.id)
                LinearGradient(colors: [BrowserStyle.raised.opacity(0), BrowserStyle.raised], startPoint: .center, endPoint: .bottom)
            }
        }
        .clipped()
    }

    @ViewBuilder
    private var actions: some View {
        if playable {
            Button { onPlay(shown, inProgress) } label: {
                Label(inProgress ? "Resume" : "Play", systemImage: "play.fill")
                    .scaledFont(size: 16, weight: .semibold)
                    .padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(BrowserStyle.ground)
                    .background(BrowserStyle.accent, in: Capsule())
            }
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))) {
                if inProgress { wide("Start over") { onPlay(shown, false) } }
                wide(watched ? "Mark unwatched" : "Mark watched") { Task { await mark(!watched) } }
                    .disabled(marking)
            }
        } else {
            NavigationLink(value: shown) {
                Label("Open series", systemImage: "chevron.right")
                    .scaledFont(size: 16, weight: .semibold)
                    .padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(BrowserStyle.ground)
                    .background(BrowserStyle.accent, in: Capsule())
            }
        }
    }

    private func wide(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).scaledFont(size: 15).foregroundStyle(BrowserStyle.text)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(Capsule().stroke(BrowserStyle.line))
        }
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
