import JellyfinKit
import PlayerCore
import SwiftUI
import TVServices

/// Home, one tab per video library, Search, along the top. A title opens its page; Play opens the
/// player over everything.
struct TVTabsView: View {
    @Environment(AppModel.self) private var model
    let session: SignedInSession
    @State private var home: HomeModel?
    @State private var libraries: [BaseItem] = []
    @State private var librariesError: String?
    @State private var showPlayer = false
    @State private var lastPlayedID: String?
    @State private var tab = "home"
    @State private var homePath = NavigationPath()
    /// Bumped when playback ends, so open title pages fetch their progress again.
    @State private var playbackEnded = 0

    var body: some View {
        TabView(selection: $tab) {
            page(path: $homePath) {
                if let home {
                    TVHomeView(home: home, session: session, librariesError: librariesError,
                               onRetryLibraries: { Task { await loadLibraries() } })
                } else {
                    ProgressView()
                }
            }
            .tabItem { Text("Tiny Jellyfin") }
            .tag("home")

            ForEach(libraries) { library in
                page { TVLibraryView(parentId: library.id, title: library.displayName) }
                    .tabItem { Text(library.displayName) }
                    .tag(library.id)
            }

            page { TVSearchView() }
                .tabItem { Image(systemName: "magnifyingglass").accessibilityLabel("Search") }
                .tag("search")
        }
        .fullScreenCover(isPresented: $showPlayer) {
            TVPlayerView { showPlayer = false }
        }
        .environment(\.tvPlay, TVPlayAction(play: play))
        .environment(\.tvPlaybackEnded, playbackEnded)
        .onChange(of: model.player.status) { was, now in
            // Playback ended: positions on the server changed, so Home and the played item follow.
            guard now == .idle || now == .ended, was != .idle, lastPlayedID != nil else { return }
            playbackEnded += 1
            Task { await home?.refreshProgress() }
            TVTopShelfContentProvider.topShelfContentDidChange()
        }
        .onOpenURL(perform: open)
        .task {
            guard home == nil, let client = model.client else { return }
            let home = HomeModel(service: client)
            self.home = home
            async let libs: Void = loadLibraries()
            await home.load()
            await libs
            #if DEBUG
            // Screenshot hooks (simctl launch with SIMCTL_CHILD_…): TJ_BROWSER_TAB=<library name>|Search,
            // TJ_AUTOPLAY=1 plays the hero (TJ_TV_PANEL in the player opens the panel).
            let env = ProcessInfo.processInfo.environment
            if let name = env["TJ_BROWSER_TAB"] { tab = libraries.first { $0.displayName == name }?.id ?? name.lowercased() }
            if env["TJ_AUTOPLAY"] != nil, let hero = home.hero { play(hero, resume: true) }
            // TJ_TV_OPEN=hero opens the hero's page, =series the series of the first Next up episode.
            switch env["TJ_TV_OPEN"] {
            case "hero"?: if let hero = home.hero { homePath.append(hero) }
            case "series"?:
                if let episode = home.rows.first(where: { $0.id == "nextUp" })?.items.first, let id = episode.seriesId {
                    homePath.append(BaseItem(id: id, name: episode.seriesName, type: .series))
                }
            default: break
            }
            #endif
        }
    }

    /// Each tab keeps its own navigation; titles push their page.
    @ViewBuilder
    private func page<Content: View>(path: Binding<NavigationPath>? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        let root = content().navigationDestination(for: BaseItem.self) { TVDetailView(item: $0) }
        if let path { NavigationStack(path: path) { root } } else { NavigationStack { root } }
    }

    private func loadLibraries() async {
        guard let client = model.client else { return }
        do {
            libraries = try await client.libraries()
            librariesError = nil
        } catch {
            librariesError = describe(error)
        }
    }

    private func play(_ item: BaseItem, resume: Bool) {
        lastPlayedID = item.id
        model.play(item, resume: resume)
        showPlayer = true
    }

    /// Top Shelf: `tinyjellyfin://play/<id>` resumes the item, `tinyjellyfin://item/<id>` opens its page.
    private func open(_ url: URL) {
        guard let link = TopShelfLink(url: url), let client = model.client else { return }
        Task {
            guard let item = try? await client.item(id: link.itemId) else { return }
            if link.play {
                play(item, resume: true)
            } else {
                tab = "home"
                homePath = NavigationPath([item])
            }
        }
    }
}

/// Starts playback from anywhere under the tabs.
struct TVPlayAction {
    var play: (BaseItem, Bool) -> Void = { _, _ in }
    func callAsFunction(_ item: BaseItem, resume: Bool) { play(item, resume) }
}

extension EnvironmentValues {
    @Entry var tvPlay = TVPlayAction()
    @Entry var tvPlaybackEnded = 0
}

/// A card that lifts when focused, like the system's: the remote's focus is the only pointer.
struct TVCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Lift(configuration: configuration) }

    private struct Lift: View {
        @Environment(\.isFocused) private var focused
        let configuration: Configuration

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 1.02 : focused ? 1.08 : 1, anchor: .top)
                .shadow(color: .black.opacity(focused ? 0.6 : 0), radius: 24, y: 18)
                .animation(.easeOut(duration: 0.18), value: focused)
        }
    }
}

/// A row of cards that scrolls sideways as focus moves along it.
struct TVShelf: View {
    let title: String
    let items: [BaseItem]
    let shape: RowShape
    var inSeries = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !title.isEmpty {
                Text(title).font(.system(size: 34, weight: .semibold)).foregroundStyle(BrowserStyle.text)
                    .padding(.horizontal, TVStyle.side)
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: TVStyle.cardGap) {
                    ForEach(items) { item in TVCard(item: item, shape: shape, inSeries: inSeries) }
                }
                .padding(.horizontal, TVStyle.side)
                .padding(.vertical, 30) // room for the lift
            }
            .scrollClipDisabled()
            .padding(.top, -30)
        }
    }
}

/// A title's card; clicking it opens the title's page.
struct TVCard: View {
    let item: BaseItem
    let shape: RowShape
    var inSeries = false

    var body: some View {
        NavigationLink(value: item) {
            ItemCard(item: item, shape: shape, selected: false,
                     width: shape == .poster ? TVStyle.posterWidth : TVStyle.stillWidth, inSeries: inSeries)
        }
        .buttonStyle(TVCardButtonStyle())
    }
}

/// A filter or genre that can be focused and clicked.
struct TVPill: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 24, weight: on ? .semibold : .regular))
        }
        .buttonStyle(PillStyle(on: on))
    }

    private struct PillStyle: ButtonStyle {
        let on: Bool
        func makeBody(configuration: Configuration) -> some View { Look(on: on, configuration: configuration) }

        struct Look: View {
            @Environment(\.isFocused) private var focused
            let on: Bool
            let configuration: Configuration

            var body: some View {
                configuration.label
                    .foregroundStyle(focused || on ? BrowserStyle.ground : BrowserStyle.dim)
                    .padding(.horizontal, 26)
                    .frame(height: 52)
                    .background(focused ? Color.white : on ? BrowserStyle.text : .clear, in: Capsule())
                    .overlay(Capsule().stroke(on || focused ? .clear : BrowserStyle.line, lineWidth: 2))
                    .scaleEffect(focused ? 1.06 : 1)
                    .animation(.easeOut(duration: 0.15), value: focused)
            }
        }
    }
}
