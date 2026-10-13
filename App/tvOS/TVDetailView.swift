import JellyfinKit
import SwiftUI

/// A title's page: backdrop, facts and badges, overview, Resume or Play, Start over, Mark watched.
/// A series adds a season strip and its episodes; an episode opens its own page.
struct TVDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tvPlay) private var play
    @Environment(\.tvPlaybackEnded) private var playbackEnded
    let item: BaseItem
    @State private var details: BaseItem?
    @State private var series: SeriesModel?
    @State private var marking = false
    @State private var markError: String?

    private var shown: BaseItem { details ?? item }
    private var isSeries: Bool { shown.type == .series }
    private var inProgress: Bool { shown.resumePositionSeconds != nil }
    private var watched: Bool { shown.userData?.played == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                ZStack(alignment: .bottomLeading) {
                    TVBackdrop(item: shown).frame(height: isSeries ? 720 : 1000)
                    info.padding(.horizontal, TVStyle.side).padding(.bottom, isSeries ? 20 : 120)
                }
                if let series { episodes(series) }
            }
            .padding(.bottom, 80)
        }
        .ignoresSafeArea(edges: .top)
        .task(id: playbackEnded) {
            guard let client = model.client else { return }
            details = (try? await client.item(id: item.id)) ?? details
            if isSeries || item.type == .series {
                if let series { await series.refresh() } else {
                    let series = SeriesModel(series: item, service: client)
                    self.series = series
                    await series.load()
                }
            }
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 20) {
            if shown.type == .episode, let name = shown.seriesName {
                Text(name).font(.system(size: 30, weight: .medium)).foregroundStyle(BrowserStyle.dim)
            }
            Text(shown.displayName)
                .font(.system(size: 80, weight: .bold)).foregroundStyle(BrowserStyle.text)
                .lineLimit(2).minimumScaleFactor(0.6)
            HStack(spacing: 14) {
                Text(ItemLabels.facts(shown)).font(.system(size: 26)).foregroundStyle(BrowserStyle.dim)
                ForEach(shown.formatBadges, id: \.self) { badge in
                    Text(badge).font(.system(size: 20, weight: .semibold)).foregroundStyle(BrowserStyle.dim)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(BrowserStyle.line, lineWidth: 2))
                }
            }
            if let overview = shown.overview, !overview.isEmpty {
                Text(overview).font(.system(size: 26)).lineSpacing(6).lineLimit(4)
                    .foregroundStyle(Color(red: 0xd6 / 255, green: 0xd2 / 255, blue: 0xcb / 255))
            }
            HStack(spacing: 22) { actions }
                .buttonBorderShape(.capsule)
                .padding(.top, 10)
            if let markError {
                Text(markError).font(.system(size: 22)).foregroundStyle(.red)
            } else if let next = series?.nextUp {
                Text([next.displayName, ItemLabels.timeLeft(next)].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 22)).foregroundStyle(BrowserStyle.muted)
            } else if !isSeries, let left = ItemLabels.timeLeft(shown) {
                Text(left).font(.system(size: 22)).foregroundStyle(BrowserStyle.muted)
            }
        }
        .frame(width: 1000, alignment: .leading)
    }

    @ViewBuilder
    private var actions: some View {
        if isSeries {
            if let next = series?.nextUp {
                let resume = next.resumePositionSeconds != nil
                Button { play(next, resume: resume) } label: {
                    Label("\(resume ? "Resume" : "Play") \(next.episodeLabel?.replacingOccurrences(of: " · ", with: " ") ?? "")",
                          systemImage: "play.fill")
                }
            }
        } else if shown.type?.isPlayable == true {
            Button { play(shown, resume: inProgress) } label: {
                Label(inProgress ? "Resume" : "Play", systemImage: "play.fill")
            }
            if inProgress { Button("Start over") { play(shown, resume: false) } }
        }
        Button(watched ? "Mark unwatched" : "Mark watched") { Task { await mark(!watched) } }
            .disabled(marking)
    }

    private func episodes(_ series: SeriesModel) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            if let error = series.error {
                InlineError(message: error) { Task { await series.load() } }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(series.seasons) { season in
                        TVPill(title: season.displayName, on: season.id == series.season?.id) {
                            Task { await series.select(season) }
                        }
                    }
                }
                .padding(.horizontal, TVStyle.side).padding(.vertical, 12)
            }
            .scrollClipDisabled()
            TVShelf(title: series.season?.displayName ?? "Episodes", items: series.episodes, shape: .still)
        }
    }

    private func mark(_ played: Bool) async {
        guard let client = model.client else { return }
        marking = true
        defer { marking = false }
        do {
            let data = try await client.markPlayed(shown.id, played: played)
            var updated = shown
            updated.userData = data
            if !played { updated.userData?.playbackPositionTicks = 0 }
            details = updated
            markError = nil
            await series?.refresh()
        } catch {
            markError = describe(error)
        }
    }
}
