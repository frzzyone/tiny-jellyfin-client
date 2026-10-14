import JellyfinKit
import SwiftUI

/// Home: the hero, then every row that has something in it, then the keyboard hints.
struct HomeView: View {
    @Environment(BrowserModel.self) private var browser
    let home: HomeModel
    var surpriseError: String?
    let onPlay: (BaseItem, Bool) -> Void
    let onOpenSeries: (BaseItem) -> Void
    let onSurprise: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    if let hero = home.hero {
                        HeroView(item: hero, selected: browser.selection == .hero, onPlay: onPlay, onOpen: onOpenSeries)
                            .id("hero")
                    } else if let error = home.heroError {
                        InlineError(message: error) { Task { await home.load() } }
                    } else if home.isLoading {
                        ProgressView().frame(maxWidth: .infinity).frame(height: 200)
                    } else if home.isEmpty {
                        Text(HomeModel.emptyMessage).foregroundStyle(BrowserStyle.muted).padding(.vertical, 40)
                    }
                    ForEach(home.visibleRows) { row in
                        RowView(row: row, onOpen: onOpenSeries, onGenre: { id in Task { await home.selectGenre(id) } },
                                onRetry: { Task { await home.load() } })
                            .id(row.id)
                    }
                    SurpriseView(error: surpriseError, onSurprise: onSurprise)
                    footer
                }
                .padding(.horizontal, BrowserStyle.sidePadding)
                .padding(.top, 22)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: browser.selection?.row) { _, row in
                if let row { withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(row, anchor: .center) } }
            }
        }
        .onAppear(perform: publishRows)
        .onChange(of: home.visibleRows) { _, _ in publishRows() }
        .onChange(of: home.hero) { _, _ in publishRows() }
    }

    private func publishRows() {
        var rows: [(layout: RowLayout, items: [BaseItem])] = []
        if let hero = home.hero { rows.append((RowLayout(id: "hero", count: 1), [hero])) }
        for row in home.visibleRows {
            rows.append((RowLayout(id: row.id, count: row.items.count), row.items))
        }
        browser.setRows(rows, owner: "home")
    }

    private var footer: some View {
        HStack(spacing: 22) {
            KeyHint(keys: ["↑", "↓"], text: "rows, up to the tabs")
            KeyHint(keys: ["←", "→"], text: "titles")
            KeyHint(keys: ["⏎"], text: "play")
            KeyHint(keys: ["space"], text: "quick look")
            KeyHint(keys: ["S"], text: "surprise me")
            KeyHint(keys: ["⌘1", "⌘2"], text: "tabs")
            KeyHint(keys: ["⌘F"], text: "search")
        }
        .padding(.top, 6)
    }
}

/// Where you left off: backdrop, title, time left, Resume and Start over.
struct HeroView: View {
    @Environment(AppModel.self) private var model
    let item: BaseItem
    let selected: Bool
    let onPlay: (BaseItem, Bool) -> Void
    let onOpen: (BaseItem) -> Void

    private var inProgress: Bool { item.resumePositionSeconds != nil }
    private var playable: Bool { item.type?.isPlayable ?? false }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(url: model.client?.backdropImageURL(for: item, maxWidth: 1600), title: "", toneID: item.id)
            LinearGradient(stops: [.init(color: BrowserStyle.ground.opacity(0), location: 0),
                                   .init(color: BrowserStyle.ground.opacity(0.55), location: 0.55),
                                   .init(color: BrowserStyle.ground.opacity(0.96), location: 1)],
                           startPoint: UnitPoint(x: 0.5, y: 0.2), endPoint: .bottom)
            VStack(alignment: .leading, spacing: 14) {
                Text(inProgress ? "Where you left off" : (item.type == .episode ? "Next up" : "Just added"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BrowserStyle.dim)
                Text(ItemLabels.title(item))
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(BrowserStyle.text)
                    .lineLimit(2)
                Text(ItemLabels.detail(item))
                    .font(.system(size: 14))
                    .foregroundStyle(BrowserStyle.dim)
                if let pct = item.userData?.playedPercentage, inProgress {
                    ProgressLine(fraction: pct / 100).frame(width: 320).clipShape(Capsule())
                }
                HStack(spacing: 14) {
                    if playable {
                        ActionButton(title: inProgress ? "Resume" : "Play", icon: "play.fill", role: .primary) { onPlay(item, inProgress) }
                        if inProgress { ActionButton(title: "Start over") { onPlay(item, false) } }
                    } else {
                        ActionButton(title: "Open", icon: "chevron.right", role: .primary) { onOpen(item) }
                    }
                    KeyHint(keys: ["⏎"], text: inProgress ? "resumes" : "plays").padding(.leading, 6)
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 36)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 440)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            if selected { RoundedRectangle(cornerRadius: 13).stroke(BrowserStyle.text, lineWidth: 2).padding(-3) }
        }
    }
}

/// One row: its header, the genre pills when it has them, and the strip of cards.
struct RowView: View {
    @Environment(BrowserModel.self) private var browser
    let row: HomeRow
    let onOpen: (BaseItem) -> Void
    let onGenre: (String) -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(row.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(BrowserStyle.text)
                if !row.genres.isEmpty {
                    GenreStrip(genres: row.genres, selected: row.genreId, onSelect: onGenre)
                } else if let subtitle = row.subtitle {
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(BrowserStyle.muted)
                }
            }
            if let error = row.error {
                InlineError(message: error, retry: onRetry)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: BrowserStyle.rowGap) {
                            ForEach(Array(row.items.enumerated()), id: \.element.id) { index, item in
                                let selected = browser.selection == BrowserSelection(row: row.id, index: index)
                                ItemCard(item: item, shape: row.shape, selected: selected)
                                    .id(item.id)
                                    .onTapGesture { browser.openQuickLook(item, in: row.items) }
                                    .onTapGesture(count: 2) { onOpen(item) }
                                    .cardAccessibility { browser.openQuickLook(item, in: row.items) }
                            }
                        }
                        .padding(4) // room for the selection outline
                    }
                    .padding(-4)
                    .onChange(of: browser.selection) { _, selection in
                        guard let selection, selection.row == row.id, row.items.indices.contains(selection.index) else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(row.items[selection.index].id, anchor: .center) }
                    }
                }
            }
        }
    }
}

/// The genres of the genre row, as pills; the first six plus a menu for the rest.
struct GenreStrip: View {
    let genres: [NameGuidPair]
    let selected: String?
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(genres.prefix(6)) { genre in
                Pill(title: genre.name ?? "?", on: genre.id == selected) { onSelect(genre.id) }
            }
            if genres.count > 6 {
                Menu {
                    ForEach(genres.dropFirst(6)) { genre in
                        Button(genre.name ?? "?") { onSelect(genre.id) }
                    }
                } label: {
                    Text("More…").font(.system(size: 13)).foregroundStyle(BrowserStyle.dim)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }
}

/// One random unwatched film, straight into the quick look.
struct SurpriseView: View {
    var error: String?
    let onSurprise: () -> Void

    var body: some View {
        HStack(spacing: 22) {
            ActionButton(title: "Surprise me", icon: "shuffle", role: .primary, action: onSurprise)
            VStack(alignment: .leading, spacing: 4) {
                Text("One random film you haven't seen, straight into the quick look")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(BrowserStyle.text)
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 13)).foregroundStyle(BrowserStyle.muted)
                } else {
                    Text("Press again for another.").font(.system(size: 13)).foregroundStyle(BrowserStyle.muted)
                }
            }
            Spacer()
            KeyCap(label: "S")
        }
        .padding(.horizontal, 26).padding(.vertical, 22)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(BrowserStyle.line))
    }
}
