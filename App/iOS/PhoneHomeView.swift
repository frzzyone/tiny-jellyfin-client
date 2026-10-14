import JellyfinKit
import SwiftUI

/// Home on the phone: the app name, where you left off, then every row with something in it.
struct PhoneHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(BrowserModel.self) private var browser
    let home: HomeModel
    let session: SignedInSession
    /// The library tabs failed to load: say so here, since there is no tab to show it in.
    var librariesError: String?
    var onRetryLibraries: () -> Void = {}
    let onPlay: (BaseItem, Bool) -> Void
    @State private var surpriseError: String?
    @State private var showAcknowledgements = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let librariesError {
                    InlineError(message: "Couldn't load your libraries. \(librariesError)", retry: onRetryLibraries)
                }
                if let hero = home.hero {
                    PhoneHero(item: hero, onPlay: onPlay, onOpen: { browser.openQuickLook(hero, in: [hero]) })
                } else if let error = home.heroError {
                    InlineError(message: error) { Task { await home.load() } }
                } else if home.isLoading {
                    ProgressView().frame(maxWidth: .infinity).frame(height: 300)
                } else if home.isEmpty {
                    Text(HomeModel.emptyMessage).foregroundStyle(BrowserStyle.muted).padding(PhoneStyle.side)
                }
                ForEach(home.visibleRows) { row in
                    if let error = row.error {
                        InlineError(message: error) { Task { await home.load() } }
                    } else {
                        PhoneRow(title: row.title, items: row.items, shape: row.shape)
                        if !row.genres.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(row.genres) { genre in
                                        Pill(title: genre.name ?? "?", on: genre.id == row.genreId) {
                                            Task { await home.selectGenre(genre.id) }
                                        }
                                    }
                                }
                                .padding(.horizontal, PhoneStyle.side)
                            }
                            .padding(.top, -12)
                        }
                    }
                }
                surprise
            }
            .padding(.bottom, 24)
        }
        .background(BrowserStyle.ground)
        .refreshable { await home.load() }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAcknowledgements) {
            NavigationStack {
                AcknowledgementsView()
                    .toolbar { Button("Done") { showAcknowledgements = false } }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image("Mark").resizable().scaledToFit().frame(width: 22, height: 22).accessibilityHidden(true)
            Text("Kinema").font(.system(size: 26, weight: .bold)).foregroundStyle(BrowserStyle.text)
            Spacer()
            Menu {
                Text(session.userName)
                Text(session.server.name)
                Button("Acknowledgements") { showAcknowledgements = true }
                Button("Sign Out", role: .destructive) { Task { await model.session.signOut() } }
            } label: {
                Text(String(session.userName.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BrowserStyle.text)
                    .frame(width: 32, height: 32)
                    .background(BrowserStyle.raised, in: Circle())
                    .overlay(Circle().stroke(BrowserStyle.line))
            }
            .accessibilityLabel("Account")
        }
        .padding(.horizontal, PhoneStyle.side)
        .padding(.top, 8)
    }

    private var surprise: some View {
        VStack(alignment: .leading, spacing: 8) {
            ActionButton(title: "Surprise me", icon: "shuffle", role: .primary) {
                Task {
                    do {
                        if let pick = try await home.surprise() { browser.openQuickLook(pick, in: [pick]) }
                        else { surpriseError = "Nothing unwatched left to pick from." }
                    } catch {
                        surpriseError = describe(error)
                    }
                }
            }
            Text(surpriseError ?? "One random film you haven't seen.")
                .font(.system(size: 13)).foregroundStyle(BrowserStyle.muted)
        }
        .padding(.horizontal, PhoneStyle.side)
    }
}

/// Where you left off: backdrop, title, time left, Resume and Start over.
struct PhoneHero: View {
    @Environment(AppModel.self) private var model
    let item: BaseItem
    let onPlay: (BaseItem, Bool) -> Void
    let onOpen: () -> Void

    private var inProgress: Bool { item.resumePositionSeconds != nil }
    private var playable: Bool { item.type?.isPlayable ?? false }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(url: model.client?.backdropImageURL(for: item, maxWidth: 1000), title: "", toneID: item.id)
                .onTapGesture(perform: onOpen)
            LinearGradient(stops: [.init(color: BrowserStyle.ground.opacity(0), location: 0.25),
                                   .init(color: BrowserStyle.ground.opacity(0.95), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 8) {
                Text(inProgress ? "Where you left off" : (item.type == .episode ? "Next up" : "Just added"))
                    .font(.system(size: 12)).foregroundStyle(BrowserStyle.dim)
                Text(ItemLabels.title(item))
                    .font(.system(size: 30, weight: .bold)).foregroundStyle(BrowserStyle.text).lineLimit(2)
                Text(ItemLabels.detail(item)).font(.system(size: 13)).foregroundStyle(BrowserStyle.dim).lineLimit(1)
                if let pct = item.userData?.playedPercentage, inProgress {
                    ProgressLine(fraction: pct / 100).clipShape(Capsule())
                }
                HStack(spacing: 10) {
                    if playable {
                        Button { onPlay(item, inProgress) } label: {
                            Label(inProgress ? "Resume" : "Play", systemImage: "play.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .foregroundStyle(BrowserStyle.ground)
                                .background(BrowserStyle.accent, in: Capsule())
                        }
                        if inProgress { ActionButton(title: "Start over") { onPlay(item, false) } }
                    } else {
                        ActionButton(title: "Open", icon: "chevron.right", role: .primary, action: onOpen)
                    }
                }
                .padding(.top, 4)
            }
            .padding(18)
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, PhoneStyle.side)
    }
}
