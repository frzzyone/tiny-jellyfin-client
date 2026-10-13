import JellyfinKit
import SwiftUI

/// A library tab: title and count, filter pills, genres, and a poster grid that pages as focus
/// moves down it.
struct TVLibraryView: View {
    @Environment(AppModel.self) private var model
    let parentId: String?
    let title: String
    var searchTerm = ""
    @State private var grid: LibraryGridModel?
    @State private var genres: [NameGuidPair] = []

    private let columns = Array(repeating: GridItem(.fixed(TVStyle.posterWidth), spacing: 30, alignment: .top), count: 7)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if searchTerm.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Text(title).font(.system(size: 52, weight: .bold)).foregroundStyle(BrowserStyle.text)
                        if let total = grid?.total {
                            Text("\(total)").font(.system(size: 24)).foregroundStyle(BrowserStyle.muted)
                        }
                    }
                    .padding(.horizontal, TVStyle.side)
                }
                if let grid {
                    filters(grid)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 40) {
                        ForEach(grid.items) { item in
                            TVCard(item: item, shape: .poster).task { await grid.itemAppeared(item) }
                        }
                    }
                    .padding(.horizontal, TVStyle.side)
                    .padding(.top, 16)
                    if let error = grid.error {
                        InlineError(message: error) { Task { await grid.retry() } }
                    } else if grid.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    } else if grid.items.isEmpty {
                        Text(grid.searchTerm.isEmpty ? "Nothing here with these filters." : "Nothing matches \u{201C}\(grid.searchTerm)\u{201D}.")
                            .font(.system(size: 26)).foregroundStyle(BrowserStyle.muted)
                            .frame(maxWidth: .infinity).padding(60)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(80)
                }
            }
            .padding(.bottom, 80)
        }
        .task {
            guard grid == nil, let client = model.client else { return }
            let grid = LibraryGridModel(parentId: parentId, filter: parentId == nil ? .az : .unwatched) { try await client.items($0) }
            self.grid = grid
            async let genreList = (try? client.genres(libraryId: parentId)) ?? []
            if searchTerm.isEmpty { await grid.loadMore() } else { await grid.apply(searchTerm: searchTerm) }
            genres = await genreList
        }
        .task(id: searchTerm) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await grid?.apply(searchTerm: searchTerm)
        }
    }

    private func filters(_ grid: LibraryGridModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            pills {
                ForEach(LibraryFilter.allCases) { filter in
                    TVPill(title: filter.title, on: grid.filter == filter) { Task { await grid.apply(filter: filter) } }
                }
            }
            if !genres.isEmpty {
                pills {
                    ForEach(genres) { genre in
                        TVPill(title: genre.name ?? "?", on: grid.genreId == genre.id) {
                            Task { await grid.apply(genreId: grid.genreId == genre.id ? nil : genre.id) }
                        }
                    }
                }
            }
        }
    }

    private func pills<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14, content: content)
                .padding(.horizontal, TVStyle.side).padding(.vertical, 12)
        }
        .scrollClipDisabled()
    }
}

/// The system search screen (keyboard and dictation), with matches from every library below it.
struct TVSearchView: View {
    @State private var text = ""

    var body: some View {
        Group {
            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Search films and series by title.")
                    .font(.system(size: 26)).foregroundStyle(BrowserStyle.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TVLibraryView(parentId: nil, title: "Search", searchTerm: text)
            }
        }
        .searchable(text: $text, prompt: "Title")
    }
}
