import JellyfinKit
import SwiftUI

enum SidebarSelection: Hashable {
    case home
    case library(String)
}

struct LibraryRootView: View {
    @Environment(AppModel.self) private var model
    let session: SignedInSession
    @State private var selection: SidebarSelection? = .home
    @State private var libraries: Loader<[BaseItem]>?
    @State private var path: [BaseItem] = []

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Home", systemImage: "house").tag(SidebarSelection?.some(.home))
                Section("Libraries") {
                    switch libraries?.state {
                    case .loaded(let items)?:
                        ForEach(items) { library in
                            Label(library.displayName,
                                  systemImage: library.collectionType == "tvshows" ? "tv" : "film")
                                .tag(SidebarSelection?.some(.library(library.id)))
                        }
                    case .failed(let message)?:
                        InlineError(message: message) { Task { await libraries?.load() } }
                    default:
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Image(systemName: "person.crop.circle")
                    Text(session.userName).lineLimit(1)
                    Spacer()
                    Button("Sign Out") { Task { await model.session.signOut() } }
                        .buttonStyle(.borderless)
                }
                .font(.callout)
                .padding(10)
            }
        } detail: {
            NavigationStack(path: $path) {
                Group {
                    switch selection {
                    case .library(let id)?:
                        if let library = libraries?.state.value?.first(where: { $0.id == id }) {
                            LibraryGridView(library: library).id(id)
                        }
                    default:
                        HomeView()
                    }
                }
                .navigationDestination(for: BaseItem.self) { item in
                    destination(for: item)
                }
            }
        }
        .task {
            guard let client = model.client else { return }
            let loader = Loader { try await client.libraries() }
            libraries = loader
            await loader.load()
        }
        .onChange(of: selection) { _, _ in path = [] }
    }

    @ViewBuilder
    private func destination(for item: BaseItem) -> some View {
        switch item.type {
        case .series?: SeriesView(series: item)
        case .season?: SeasonView(season: item)
        default: ItemDetailsView(itemId: item.id)
        }
    }
}

extension BaseItem: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var resume: Loader<[BaseItem]>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch resume?.state {
                case .loaded(let items)? where !items.isEmpty:
                    Text("Continue Watching").font(.title2.bold())
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(items) { item in
                                NavigationLink(value: item) { ResumeCard(item: item) }.buttonStyle(.plain)
                            }
                        }
                    }
                case .loaded?:
                    // Continue Watching is hidden when nothing is in progress.
                    ContentUnavailableView("Pick a library", systemImage: "film.stack",
                                           description: Text("Choose a library in the sidebar to start browsing."))
                case .failed(let message)?:
                    InlineError(message: message) { Task { await resume?.load() } }
                default:
                    ProgressView()
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Home")
        .task {
            guard let client = model.client else { return }
            let loader = Loader { try await client.resumeItems() }
            resume = loader
            await loader.load()
        }
    }
}

struct ResumeCard: View {
    @Environment(AppModel.self) private var model
    let item: BaseItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImage(url: model.client?.primaryImageURL(for: item, maxHeight: 360), title: item.displayName)
                .frame(width: 150, height: 225)
                .overlay(alignment: .bottom) {
                    GeometryReader { geo in
                        let fraction = (item.userData?.playedPercentage ?? 0) / 100
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.black.opacity(0.5))
                            Rectangle().fill(Color.accentColor).frame(width: geo.size.width * fraction)
                        }
                    }
                    .frame(height: 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(item.seriesName ?? item.displayName).font(.callout.bold()).lineLimit(1)
            if item.seriesName != nil {
                Text([item.episodeLabel, item.name].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 150)
    }
}

struct LibraryGridView: View {
    @Environment(AppModel.self) private var model
    let library: BaseItem
    @State private var grid: LibraryGridModel?

    var body: some View {
        ScrollView {
            if let grid {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 18)], spacing: 22) {
                    ForEach(grid.items) { item in
                        NavigationLink(value: item) { PosterCell(item: item) }
                            .buttonStyle(.plain)
                            .task { await grid.itemAppeared(item) }
                    }
                }
                .padding(20)
                if let error = grid.error {
                    InlineError(message: error) { Task { await grid.retry() } }.padding()
                } else if grid.isLoading {
                    ProgressView().padding()
                }
            }
        }
        .navigationTitle(library.displayName)
        .task {
            guard grid == nil, let client = model.client else { return }
            let model = LibraryGridModel { start, limit in
                try await client.items(parentId: library.id, startIndex: start, limit: limit)
            }
            grid = model
            await model.loadMore()
        }
    }
}

struct PosterCell: View {
    @Environment(AppModel.self) private var model
    let item: BaseItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImage(url: model.client?.primaryImageURL(for: item), title: item.displayName)
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if item.userData?.played == true {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, .green).padding(6)
                    }
                }
            Text(item.displayName).font(.callout).lineLimit(1)
            if let year = item.productionYear {
                Text(String(year)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Poster with a title placeholder when the item has no artwork or it fails to load.
struct PosterImage: View {
    let url: URL?
    let title: String

    var body: some View {
        ZStack {
            placeholder
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

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [.gray.opacity(0.35), .gray.opacity(0.15)], startPoint: .top, endPoint: .bottom)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }
}

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
                                Text("\(unplayed) unwatched").foregroundStyle(.secondary).font(.caption)
                            } else if season.userData?.played == true {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
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

struct SeasonView: View {
    @Environment(AppModel.self) private var model
    let season: BaseItem
    @State private var episodes: Loader<[BaseItem]>?

    var body: some View {
        List {
            switch episodes?.state {
            case .loaded(let items)?:
                ForEach(items) { episode in
                    NavigationLink(value: episode) {
                        HStack(spacing: 12) {
                            Text(episode.indexNumber.map { "\($0)" } ?? "–")
                                .font(.body.monospacedDigit()).foregroundStyle(.secondary).frame(width: 28)
                            Text(episode.displayName)
                            Spacer()
                            if episode.userData?.played == true {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    .accessibilityLabel("Watched")
                            } else if let pct = episode.userData?.playedPercentage, pct > 0 {
                                ProgressView(value: pct, total: 100).frame(width: 50)
                            }
                        }
                    }
                }
            case .failed(let message)?:
                InlineError(message: message) { Task { await episodes?.load() } }
            default:
                ProgressView()
            }
        }
        .navigationTitle([season.seriesName, season.name].compactMap { $0 }.joined(separator: " — "))
        .task {
            guard episodes == nil, let client = model.client, let seriesId = season.seriesId else { return }
            let loader = Loader { try await client.episodes(seriesId: seriesId, seasonId: season.id) }
            episodes = loader
            await loader.load()
        }
    }
}

struct ItemDetailsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let itemId: String
    @State private var details: Loader<BaseItem>?

    var body: some View {
        ScrollView {
            switch details?.state {
            case .loaded(let item)?:
                HStack(alignment: .top, spacing: 24) {
                    PosterImage(url: model.client?.primaryImageURL(for: item, maxHeight: 600), title: item.displayName)
                        .frame(width: 220, height: 330)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 12) {
                        if let series = item.seriesName {
                            Text(series).font(.title3).foregroundStyle(.secondary)
                        }
                        Text(item.displayName).font(.largeTitle.bold())
                        HStack(spacing: 10) {
                            if let label = item.episodeLabel { Text(label) }
                            if let date = item.dateLabel { Text(date) }
                            if let ticks = item.runTimeTicks { Text(TimeFormat.runtime(ticks: ticks)) }
                        }
                        .foregroundStyle(.secondary)
                        HStack {
                            ForEach(PlaybackActions.actions(for: item), id: \.title) { action in
                                Button {
                                    model.play(item, resume: action.resume)
                                    openWindow(id: AppModel.playerWindowID)
                                } label: {
                                    Label(action.title, systemImage: action.resume ? "play.circle" : "play.fill")
                                }
                                .controlSize(.large)
                                .buttonStyle(.borderedProminent)
                                .tint(action == PlaybackActions.actions(for: item).first ? .accentColor : .gray)
                            }
                        }
                        if let overview = item.overview {
                            Text(overview).frame(maxWidth: 640, alignment: .leading)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            case .failed(let message)?:
                InlineError(message: message) { Task { await details?.load() } }.padding(40)
            default:
                ProgressView().padding(40)
            }
        }
        .task(id: itemId) {
            guard let client = model.client else { return }
            let loader = Loader { try await client.item(id: itemId) }
            details = loader
            await loader.load()
        }
    }
}

struct InlineError: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            Button("Retry", action: retry)
        }
        .frame(maxWidth: .infinity)
    }
}
