import JellyfinKit
import SwiftUI

/// A library tab (or the search results when `parentId` is nil and there is a search term):
/// one-click filters, the genre strip, today's discovery rows for the library, and the paged grid.
struct LibraryTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(BrowserModel.self) private var browser
    let parentId: String?
    let title: String
    let searchTerm: String
    /// The library itself, for its discovery rows (none in search results).
    var library: BaseItem?
    @State private var grid: LibraryGridModel?
    @State private var discovery: HomeModel?
    @State private var genres: [NameGuidPair] = []
    @State private var columns = 6

    private static let gridID = "grid"
    private let cell: CGFloat = 150
    private let gap: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let grid {
                GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        if let discovery {
                            VStack(alignment: .leading, spacing: 30) {
                                ForEach(discovery.visibleRows) { row in
                                    RowView(row: row, onOpen: { browser.openQuickLook($0, in: row.items) },
                                            onGenre: { _ in }, onRetry: { Task { await discovery.load() } })
                                        .id(row.id)
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.bottom, discovery.visibleRows.isEmpty ? 0 : 30)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: cell, maximum: cell), spacing: gap, alignment: .top)],
                                  alignment: .leading, spacing: 18) {
                            ForEach(Array(grid.items.enumerated()), id: \.element.id) { index, item in
                                let selected = browser.selection == BrowserSelection(row: Self.gridID, index: index)
                                ItemCard(item: item, shape: .poster, selected: selected)
                                    .id(item.id)
                                    .onTapGesture { browser.openQuickLook(item, in: grid.items) }
                                    .cardAccessibility { browser.openQuickLook(item, in: grid.items) }
                                    .task { await grid.itemAppeared(item) }
                            }
                        }
                        .padding(4)
                        if let error = grid.error {
                            InlineError(message: error) { Task { await grid.retry() } }.padding()
                        } else if grid.isLoading {
                            ProgressView().padding()
                        } else if grid.items.isEmpty {
                            Text(searchTerm.isEmpty ? "Nothing here with these filters." : "Nothing matches \u{201C}\(searchTerm)\u{201D}.")
                                .foregroundStyle(BrowserStyle.muted).padding(40)
                        }
                    }
                    .onChange(of: geo.size.width, initial: true) { _, width in
                        // The adaptive grid fits as many fixed cells as the width allows; the keys need the same count.
                        columns = max(1, Int((width - 8 + gap) / (cell + gap)))
                    }
                    .onChange(of: browser.selection) { _, selection in
                        guard let selection else { return }
                        if selection.row != Self.gridID {
                            withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(selection.row, anchor: .center) }
                            return
                        }
                        guard grid.items.indices.contains(selection.index) else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(grid.items[selection.index].id, anchor: .center) }
                    }
                }
                }
                .padding(.horizontal, BrowserStyle.sidePadding - 4)
                .padding(.top, 22)
                .onChange(of: grid.items) { _, _ in publishRows() }
                .onChange(of: discovery?.visibleRows) { _, _ in publishRows() }
                .onChange(of: columns) { _, _ in publishRows() }
                .onAppear(perform: publishRows)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
            // Typing: wait for a pause before asking the server.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await grid?.apply(searchTerm: searchTerm)
        }
        .onDisappear { browser.setRows([]) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(BrowserStyle.text)
                .padding(.trailing, 8)
            if let grid {
                ForEach(LibraryFilter.allCases) { filter in
                    Pill(title: filter.title, on: grid.filter == filter) { Task { await grid.apply(filter: filter) } }
                }
                if !genres.isEmpty {
                    Rectangle().fill(BrowserStyle.line).frame(width: 1, height: 22).padding(.horizontal, 6)
                    GenreStrip(genres: genres, selected: grid.genreId) { id in
                        Task { await grid.apply(genreId: grid.genreId == id ? nil : id) }
                    }
                }
                Spacer()
                if let total = grid.total {
                    Text(grid.items.count < total ? "\(grid.items.count) of \(total)" : "\(total)")
                        .font(.system(size: 13)).foregroundStyle(BrowserStyle.muted)
                }
            }
        }
        .padding(.horizontal, BrowserStyle.sidePadding)
        .padding(.top, 24)
    }

    private func publishRows() {
        guard let grid else { return }
        let rows = (discovery?.visibleRows ?? []).map { (RowLayout(id: $0.id, count: $0.items.count), $0.items) }
        browser.setRows(rows + [(RowLayout(id: Self.gridID, count: grid.items.count, columns: columns), grid.items)])
    }
}
