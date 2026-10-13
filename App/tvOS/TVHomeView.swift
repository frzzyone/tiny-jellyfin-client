import JellyfinKit
import SwiftUI

/// Home: where you left off over its backdrop, then every row with something in it as a shelf.
struct TVHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tvPlay) private var play
    let home: HomeModel
    let session: SignedInSession
    var librariesError: String?
    var onRetryLibraries: () -> Void = {}
    @State private var surprise: BaseItem?
    @State private var surpriseError: String?
    @State private var showAcknowledgements = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 56) {
                if let hero = home.hero {
                    TVHero(item: hero)
                } else if let error = home.heroError {
                    InlineError(message: error) { Task { await home.load() } }.padding(.top, 200)
                } else if home.isLoading {
                    ProgressView().frame(maxWidth: .infinity).frame(height: 600)
                } else if home.isEmpty {
                    Text(HomeModel.emptyMessage).font(.system(size: 28)).foregroundStyle(BrowserStyle.muted)
                        .padding(.horizontal, TVStyle.side).padding(.top, 220)
                }
                if let librariesError {
                    InlineError(message: "Couldn't load your libraries. \(librariesError)", retry: onRetryLibraries)
                }
                ForEach(home.visibleRows) { row in
                    if let error = row.error {
                        InlineError(message: "\(row.title): \(error)") { Task { await home.load() } }
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            TVShelf(title: row.title, items: row.items, shape: row.shape)
                            if !row.genres.isEmpty {
                                ScrollView(.horizontal) {
                                    HStack(spacing: 14) {
                                        ForEach(row.genres) { genre in
                                            TVPill(title: genre.name ?? "?", on: genre.id == row.genreId) {
                                                Task { await home.selectGenre(genre.id) }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, TVStyle.side).padding(.vertical, 12)
                                }
                                .scrollClipDisabled()
                            }
                        }
                    }
                }
                footer
            }
            .padding(.bottom, 80)
        }
        // Backdrops run to the screen's edges; content keeps its own 90 pt margins.
        .ignoresSafeArea(edges: [.top, .horizontal])
        .navigationDestination(item: $surprise) { TVDetailView(item: $0) }
        .sheet(isPresented: $showAcknowledgements) { AcknowledgementsView() }
    }

    /// Surprise me, and who is signed in where.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 24) {
                Button {
                    Task {
                        do {
                            surprise = try await home.surprise()
                            surpriseError = surprise == nil ? "Nothing unwatched left to pick from." : nil
                        } catch {
                            surpriseError = describe(error)
                        }
                    }
                } label: {
                    Label("Surprise me", systemImage: "shuffle")
                }
                Text(surpriseError ?? "One random film you haven't seen.")
                    .font(.system(size: 22)).foregroundStyle(BrowserStyle.muted)
            }
            HStack(spacing: 24) {
                Text("\(session.userName) on \(session.server.name)")
                    .font(.system(size: 22)).foregroundStyle(BrowserStyle.muted)
                Button("Acknowledgements") { showAcknowledgements = true }
                Button("Sign Out") { Task { await model.session.signOut() } }
            }
        }
        .padding(.horizontal, TVStyle.side)
        .padding(.top, 20)
    }
}

/// Where you left off: the backdrop full width, title, time left, Resume, Start over, Details.
struct TVHero: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tvPlay) private var play
    let item: BaseItem
    @FocusState private var primaryFocused: Bool

    private var inProgress: Bool { item.resumePositionSeconds != nil }
    private var playable: Bool { item.type?.isPlayable ?? false }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TVBackdrop(item: item)
            VStack(alignment: .leading, spacing: 18) {
                Text(inProgress ? "Where you left off" : (item.type == .episode ? "Next up" : "Just added"))
                    .font(.system(size: 24)).foregroundStyle(BrowserStyle.dim)
                Text(ItemLabels.title(item))
                    .font(.system(size: 84, weight: .bold)).foregroundStyle(BrowserStyle.text)
                    .lineLimit(2).minimumScaleFactor(0.6)
                Text(ItemLabels.detail(item)).font(.system(size: 27)).foregroundStyle(BrowserStyle.dim).lineLimit(1)
                if let pct = item.userData?.playedPercentage, inProgress {
                    ProgressLine(fraction: pct / 100).frame(width: 520).clipShape(Capsule())
                }
                HStack(spacing: 22) {
                    if playable {
                        Button { play(item, resume: inProgress) } label: {
                            Label(inProgress ? "Resume" : "Play", systemImage: "play.fill")
                        }
                        .focused($primaryFocused)
                        if inProgress { Button("Start over") { play(item, resume: false) } }
                    }
                    NavigationLink("Details", value: item)
                }
                .buttonBorderShape(.capsule)
                .padding(.top, 14)
            }
            .frame(width: 900, alignment: .leading)
            .padding(.horizontal, TVStyle.side)
            .padding(.bottom, 20)
        }
        .frame(height: 760)
        // One click from launch resumes the film.
        .defaultFocus($primaryFocused, true)
    }
}

/// A title's backdrop, fading into the page on the left and at the bottom so text sits on it.
struct TVBackdrop: View {
    @Environment(AppModel.self) private var model
    let item: BaseItem

    var body: some View {
        Artwork(url: model.client?.backdropImageURL(for: item, maxWidth: 1920), title: "", toneID: item.id)
            .overlay {
                LinearGradient(stops: [.init(color: BrowserStyle.ground.opacity(0.92), location: 0),
                                       .init(color: BrowserStyle.ground.opacity(0.55), location: 0.42),
                                       .init(color: BrowserStyle.ground.opacity(0), location: 0.7)],
                               startPoint: .leading, endPoint: .trailing)
            }
            .overlay {
                LinearGradient(stops: [.init(color: BrowserStyle.ground.opacity(0), location: 0.6),
                                       .init(color: BrowserStyle.ground, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .accessibilityHidden(true)
    }
}
