import JellyfinKit
import SwiftUI

extension BaseItem: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A series: its seasons, with how much of each is left.
struct SeriesView: View {
    @Environment(AppModel.self) private var model
    let series: BaseItem
    @State private var seasons: Loader<[BaseItem]>?

    var body: some View {
        List {
            switch seasons?.state {
            case .loaded(let items)?:
                ForEach(items) { season in
                    NavigationLink(value: seasonWithSeries(season)) {
                        HStack {
                            Text(season.displayName)
                            Spacer()
                            if let unplayed = season.userData?.unplayedItemCount, unplayed > 0 {
                                Text("\(unplayed) unwatched").foregroundStyle(BrowserStyle.muted).font(.caption)
                            } else if season.userData?.played == true {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(BrowserStyle.accent)
                            }
                        }
                    }
                }
            case .failed(let message)?:
                InlineError(message: message) { Task { await seasons?.load() } }
            default:
                ProgressView()
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(series.displayName)
        .task {
            guard seasons == nil, let client = model.client else { return }
            let loader = Loader { try await client.seasons(seriesId: series.id) }
            seasons = loader
            await loader.load()
        }
    }

    private func seasonWithSeries(_ season: BaseItem) -> BaseItem {
        var copy = season
        copy.seriesId = copy.seriesId ?? series.id
        copy.seriesName = copy.seriesName ?? series.name
        return copy
    }
}

/// A season: its episodes in order. An episode opens in the quick look.
struct SeasonView: View {
    @Environment(AppModel.self) private var model
    @Environment(BrowserModel.self) private var browser
    let season: BaseItem
    @State private var episodes: Loader<[BaseItem]>?

    var body: some View {
        List {
            switch episodes?.state {
            case .loaded(let items)?:
                ForEach(items) { episode in
                    Button {
                        browser.openQuickLook(episode, in: items)
                    } label: {
                        HStack(spacing: 12) {
                            Text(episode.indexNumber.map { "\($0)" } ?? "–")
                                .font(.body.monospacedDigit()).foregroundStyle(BrowserStyle.muted).frame(width: 28)
                            Text(episode.displayName)
                            Spacer()
                            if let minutes = episode.runtimeMinutes {
                                Text(ItemLabels.minutes(minutes)).font(.caption).foregroundStyle(BrowserStyle.muted)
                            }
                            if episode.userData?.played == true {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(BrowserStyle.accent)
                                    .accessibilityLabel("Watched")
                            } else if let pct = episode.userData?.playedPercentage, pct > 0 {
                                ProgressLine(fraction: pct / 100).frame(width: 50).clipShape(Capsule())
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            case .failed(let message)?:
                InlineError(message: message) { Task { await episodes?.load() } }
            default:
                ProgressView()
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle([season.seriesName, season.name].compactMap { $0 }.joined(separator: " — "))
        .task {
            guard episodes == nil, let client = model.client, let seriesId = season.seriesId else { return }
            let loader = Loader { try await client.episodes(seriesId: seriesId, seasonId: season.id) }
            episodes = loader
            await loader.load()
        }
    }
}

struct InlineError: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(BrowserStyle.muted)
            Button("Retry", action: retry)
        }
        .frame(maxWidth: .infinity)
    }
}
