import JellyfinKit
import SwiftUI

/// A library tab: today's discovery rows for the library, filter pills, genres, and a
/// three-column poster grid that pages as it scrolls.
struct PhoneLibraryView: View {
    @Environment(AppModel.self) private var model
    let parentId: String?
    let title: String
    var searchTerm = ""
    /// Search draws its own header (with the field) above the results.
    var showsHeader = true
    /// The library itself, for its discovery rows (none in search results).
    var library: BaseItem?
    let onPlay: (BaseItem, Bool) -> Void
    @State private var grid: LibraryGridModel?
    @State private var discovery: HomeModel?
    @State private var genres: [NameGuidPair] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if showsHeader { PhoneHeader(title: title) }
                if let grid {
                    if let total = grid.total {
                        Text(grid.items.count < total ? "\(grid.items.count) of \(total)" : "\(total)")
                            .scaledFont(size: 13).foregroundStyle(BrowserStyle.muted)
                            .padding(.horizontal, PhoneStyle.side).padding(.top, showsHeader ? -6 : 0)
                    }
                    if let discovery {
                        ForEach(discovery.visibleRows) { row in
                            if let error = row.error {
                                InlineError(message: error) { Task { await discovery.load() } }
                            } else {
                                PhoneRow(title: row.title, subtitle: row.subtitle, items: row.items, shape: row.shape)
                                    .padding(.bottom, 14)
                            }
                        }
                    }
                    filters(grid)
                    PhoneGrid(grid: grid)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }
            }
            .padding(.bottom, 24)
        }
        .background(BrowserStyle.ground)
        .scrollDismissesKeyboard(.immediately)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard grid == nil, let client = model.client else { return }
            let grid = LibraryGridModel(parentId: parentId, filter: parentId == nil ? .az : .unwatched) { try await client.items($0) }
            self.grid = grid
            let discovery = library.map { HomeModel(service: client, library: $0) }
            self.discovery = discovery
            async let genreList = (try? client.genres(libraryId: parentId)) ?? []
            async let rows: Void = discovery?.load() ?? ()
            if searchTerm.isEmpty { await grid.loadMore() } else { await grid.apply(searchTerm: searchTerm) }
            genres = await genreList
            await rows
        }
        .task(id: searchTerm) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await grid?.apply(searchTerm: searchTerm)
        }
    }

    private func filters(_ grid: LibraryGridModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            pills {
                ForEach(LibraryFilter.allCases) { filter in
                    Pill(title: filter.title, on: grid.filter == filter) { Task { await grid.apply(filter: filter) } }
                }
            }
            if !genres.isEmpty {
                pills {
                    ForEach(genres) { genre in
                        Pill(title: genre.name ?? "?", on: grid.genreId == genre.id) {
                            Task { await grid.apply(genreId: grid.genreId == genre.id ? nil : genre.id) }
                        }
                    }
                }
            }
        }
        .padding(.bottom, 6)
    }

    private func pills<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8, content: content).padding(.horizontal, PhoneStyle.side)
        }
    }
}

/// Three posters across, loading more near the end.
struct PhoneGrid: View {
    @Environment(BrowserModel.self) private var browser
    let grid: LibraryGridModel
    /// Browsing is portrait-only, so the card width follows the screen.
    private let width = (UIScreen.main.bounds.width - PhoneStyle.side * 2 - 20) / 3

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: 10, alignment: .top), count: 3),
                  alignment: .leading, spacing: 14) {
            ForEach(grid.items) { item in
                Button { browser.openQuickLook(item, in: grid.items) } label: {
                    ItemCard(item: item, shape: .poster, selected: false, width: width)
                }
                .buttonStyle(.plain)
                .task { await grid.itemAppeared(item) }
            }
        }
        .padding(.horizontal, PhoneStyle.side)
        if let error = grid.error {
            InlineError(message: error) { Task { await grid.retry() } }
        } else if grid.isLoading {
            ProgressView().frame(maxWidth: .infinity).padding()
        } else if grid.items.isEmpty {
            Text(grid.searchTerm.isEmpty ? "Nothing here with these filters." : "Nothing matches \u{201C}\(grid.searchTerm)\u{201D}.")
                .foregroundStyle(BrowserStyle.muted).frame(maxWidth: .infinity).padding(40)
        }
    }
}

/// Search across every library, as you type.
struct PhoneSearchView: View {
    let onPlay: (BaseItem, Bool) -> Void
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhoneHeader(title: "Search")
            field
            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Search films and series by title.")
                    .foregroundStyle(BrowserStyle.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PhoneLibraryView(parentId: nil, title: "Search", searchTerm: text, showsHeader: false, onPlay: onPlay)
            }
        }
        .background(BrowserStyle.ground)
        .toolbar(.hidden, for: .navigationBar)
    }

    /// The system search field lives in the navigation bar, which these pages hide to match Home.
    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(BrowserStyle.muted)
            TextField("Title", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(BrowserStyle.muted)
                    .accessibilityLabel("Clear")
            }
        }
        .scaledFont(size: 16)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minHeight: 40)
        .background(BrowserStyle.raised, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, PhoneStyle.side)
    }
}

/// A tab's title, drawn like Home's header instead of a navigation bar's large title (which
/// leaves an empty bar above it).
struct PhoneHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .scaledFont(size: 26, weight: .bold)
            .foregroundStyle(BrowserStyle.text)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .padding(.horizontal, PhoneStyle.side)
            .padding(.top, 8)
    }
}
