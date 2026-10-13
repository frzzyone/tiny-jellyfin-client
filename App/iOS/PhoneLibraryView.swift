import JellyfinKit
import SwiftUI

/// A library tab: filter pills, genres, and a three-column poster grid that pages as it scrolls.
struct PhoneLibraryView: View {
    @Environment(AppModel.self) private var model
    let parentId: String?
    let title: String
    var searchTerm = ""
    let onPlay: (BaseItem, Bool) -> Void
    @State private var grid: LibraryGridModel?
    @State private var genres: [NameGuidPair] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let grid {
                    if let total = grid.total {
                        Text(grid.items.count < total ? "\(grid.items.count) of \(total)" : "\(total)")
                            .font(.system(size: 13)).foregroundStyle(BrowserStyle.muted)
                            .padding(.horizontal, PhoneStyle.side).padding(.top, -6)
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
        .navigationTitle(title)
        .task {
            guard grid == nil, let client = model.client else { return }
            let grid = LibraryGridModel(parentId: parentId, filter: parentId == nil ? .az : .unwatched) { try await client.items($0) }
            self.grid = grid
            async let genreList = (try? client.genres(libraryId: parentId)) ?? []
            if searchTerm.isEmpty { await grid.loadMore() } else { await grid.apply(searchTerm: searchTerm) }
            genres = await genreList
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
        Group {
            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Search films and series by title.")
                    .foregroundStyle(BrowserStyle.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(BrowserStyle.ground)
            } else {
                PhoneLibraryView(parentId: nil, title: "Search", searchTerm: text, onPlay: onPlay)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Title")
    }
}
