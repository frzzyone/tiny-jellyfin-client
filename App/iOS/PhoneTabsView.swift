import JellyfinKit
import PlayerCore
import SwiftUI

/// Home, one tab per video library, Search. A title opens the detail sheet; Play opens the player.
struct PhoneTabsView: View {
    @Environment(AppModel.self) private var model
    let session: SignedInSession
    @State private var browser = BrowserModel()
    @State private var home: HomeModel?
    @State private var libraries: [BaseItem] = []
    @State private var librariesError: String?
    @State private var showPlayer = false
    @State private var lastPlayedID: String?
    @State private var tab = "home"

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                if let home {
                    PhoneHomeView(home: home, session: session, librariesError: librariesError,
                                  onRetryLibraries: { Task { await loadLibraries() } }, onPlay: play)
                } else {
                    ProgressView()
                }
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag("home")

            ForEach(libraries) { library in
                NavigationStack {
                    PhoneLibraryView(parentId: library.id, title: library.displayName, onPlay: play)
                }
                .tabItem { Label(library.displayName, systemImage: library.collectionType == "tvshows" ? "tv" : "film") }
                .tag(library.id)
            }

            NavigationStack {
                PhoneSearchView(onPlay: play)
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag("search")
        }
        .tint(BrowserStyle.accent)
        .sheet(item: Binding(get: { browser.quickLook }, set: { if $0 == nil { browser.closeQuickLook() } })) { item in
            PhoneDetailSheet(item: item, onPlay: play, onUpdate: update)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showPlayer) {
            PhonePlayerView { showPlayer = false }
        }
        // Outermost, so the sheet and the player (presented outside the tabs) see it too.
        .environment(browser)
        .onChange(of: model.player.status) { was, now in
            // Playback ended: positions on the server changed, so Home and the played item follow.
            guard now == .idle || now == .ended, was != .idle, let playedID = lastPlayedID else { return }
            Task {
                await home?.refreshProgress()
                if let client = model.client, let fresh = try? await client.item(id: playedID) { update(fresh) }
            }
        }
        .task {
            guard home == nil, let client = model.client else { return }
            let home = HomeModel(service: client)
            self.home = home
            async let libs: Void = loadLibraries()
            await home.load()
            await libs
            #if DEBUG
            // Screenshot hooks (simctl launch with SIMCTL_CHILD_…): TJ_BROWSER_TAB=<library name>|Search,
            // TJ_BROWSER_QUICKLOOK=hero.
            let env = ProcessInfo.processInfo.environment
            if let name = env["TJ_BROWSER_TAB"] { tab = libraries.first { $0.displayName == name }?.id ?? name.lowercased() }
            if env["TJ_BROWSER_QUICKLOOK"] == "hero", let hero = home.hero { browser.openQuickLook(hero, in: [hero]) }
            if env["TJ_AUTOPLAY"] != nil, let hero = home.hero { play(hero, resume: true) }
            #endif
        }
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
        browser.closeQuickLook()
        lastPlayedID = item.id
        model.play(item, resume: resume)
        showPlayer = true
    }

    private func update(_ item: BaseItem) {
        home?.update(item)
        browser.update(item)
    }
}

/// The phone's sizes for the shared cards.
enum PhoneStyle {
    static let posterWidth: CGFloat = 110
    static let stillWidth: CGFloat = 220
    static let side: CGFloat = 20
}

/// A sideways-scrolling row of cards; a tap opens the detail sheet.
struct PhoneRow: View {
    @Environment(BrowserModel.self) private var browser
    let title: String
    var subtitle: String?
    let items: [BaseItem]
    let shape: RowShape

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 19, weight: .semibold)).foregroundStyle(BrowserStyle.text)
                Spacer()
                Text("\(items.count)").font(.system(size: 13)).foregroundStyle(BrowserStyle.muted)
            }
            .padding(.horizontal, PhoneStyle.side)
            if let subtitle {
                Text(subtitle).font(.system(size: 13)).foregroundStyle(BrowserStyle.muted)
                    .padding(.horizontal, PhoneStyle.side).padding(.top, -6)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(items) { item in
                        Button { browser.openQuickLook(item, in: items) } label: {
                            ItemCard(item: item, shape: shape, selected: false,
                                     width: shape == .poster ? PhoneStyle.posterWidth : PhoneStyle.stillWidth)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, PhoneStyle.side)
            }
        }
    }
}
