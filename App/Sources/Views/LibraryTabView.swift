import JellyfinKit
import SwiftUI

/// A library tab (or the search results when `parentId` is nil and there is a search term):
/// one-click filters, the genre strip, and the paged poster grid.
struct LibraryTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(BrowserModel.self) private var browser
    let parentId: String?
    let title: String
    let searchTerm: String
    @State private var grid: LibraryGridModel?
    @State private var genres: [NameGuidPair] = []
    @State private var columns = 6

    private static let gridID = "grid"
    private let cell: CGFloat = 150
    private let gap: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let grid {
                ScrollViewReader { proxy in
                    ScrollView {
                        GeometryReader { geo in
                            Color.clear.preference(key: WidthKey.self, value: geo.size.width)
                        }
                        .frame(height: 0)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: gap, alignment: .top), count: columns),
                                  alignment: .leading, spacing: 18) {
                            ForEach(Array(grid.items.enumerated()), id: \.element.id) { index, item in
                                let selected = browser.selection == BrowserSelection(row: Self.gridID, index: index)
                                ItemCard(item: item, shape: .poster, selected: selected)
                                    .id(item.id)
                                    .onTapGesture { browser.openQuickLook(item, in: grid.items) }
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
                    .onPreferenceChange(WidthKey.self) { width in
                        columns = max(1, Int((width + gap) / (cell + gap)))
                    }
                    .onChange(of: browser.selection) { _, selection in
                        guard let selection, selection.row == Self.gridID, grid.items.indices.contains(selection.index) else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(grid.items[selection.index].id, anchor: .center) }
                    }
                }
                .padding(.horizontal, BrowserStyle.sidePadding - 4)
                .padding(.top, 22)
                .onChange(of: grid.items) { _, _ in publishRows() }
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
            async let genreList = (try? client.genres(libraryId: parentId)) ?? []
            await grid.apply(searchTerm: searchTerm)
            genres = await genreList
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
        browser.setRows([(RowLayout(id: Self.gridID, count: grid.items.count, columns: columns), grid.items)])
    }
}

private struct WidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
