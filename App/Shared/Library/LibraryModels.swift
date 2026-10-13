import Foundation
import JellyfinKit
import Observation

enum LoadState<Value> {
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? { if case .loaded(let v) = self { return v }; return nil }
}

func describe(_ error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
}

/// Loads a value with an inline error + Retry. Authentication failures are handled by the
/// session (the client's 401 hook), so other errors never sign the user out.
@MainActor
@Observable
final class Loader<Value> {
    private(set) var state: LoadState<Value> = .loading
    @ObservationIgnored private let fetch: () async throws -> Value

    init(_ fetch: @escaping () async throws -> Value) {
        self.fetch = fetch
    }

    func load() async {
        state = .loading
        do {
            state = .loaded(try await fetch())
        } catch is CancellationError {
        } catch {
            state = .failed(describe(error))
        }
    }
}

/// One-click ways to cut a library down. No typing.
enum LibraryFilter: String, CaseIterable, Identifiable {
    case unwatched, recent, az, longestUnseen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unwatched: "Unwatched"
        case .recent: "Recently added"
        case .az: "A–Z"
        case .longestUnseen: "Longest unseen"
        }
    }
}

/// A poster grid with paging, filters, a genre and a search term. Any change restarts paging.
@MainActor
@Observable
final class LibraryGridModel {
    static let pageSize = 60
    let parentId: String?
    private(set) var items: [BaseItem] = []
    private(set) var total: Int?
    private(set) var error: String?
    private(set) var isLoading = false
    private(set) var filter: LibraryFilter = .unwatched
    private(set) var genreId: String?
    private(set) var searchTerm = ""
    @ObservationIgnored private let fetch: (ItemQuery) async throws -> ItemsResult
    @ObservationIgnored private var generation = 0

    init(parentId: String?, filter: LibraryFilter = .unwatched, fetch: @escaping (ItemQuery) async throws -> ItemsResult) {
        self.parentId = parentId
        self.filter = filter
        self.fetch = fetch
    }

    var hasMore: Bool { total.map { items.count < $0 } ?? true }

    /// The query behind the grid, from the current filter, genre and search.
    static func query(parentId: String?, filter: LibraryFilter, genreId: String?, searchTerm: String,
                      startIndex: Int, limit: Int = pageSize) -> ItemQuery {
        var query = ItemQuery(parentId: parentId)
        switch filter {
        case .unwatched:
            query.filters = [.unplayed]
            query.sort = .name
        case .recent:
            query.sort = .dateCreated
            query.descending = true
        case .az:
            query.sort = .name
        case .longestUnseen:
            query.filters = [.unplayed]
            query.sort = .dateCreated
        }
        query.genreIds = genreId.map { [$0] } ?? []
        query.searchTerm = searchTerm
        query.startIndex = startIndex
        query.limit = limit
        return query
    }

    var query: ItemQuery {
        Self.query(parentId: parentId, filter: filter, genreId: genreId, searchTerm: searchTerm, startIndex: items.count)
    }

    func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        let generation = self.generation
        defer { if generation == self.generation { isLoading = false } }
        do {
            let page = try await fetch(query)
            guard generation == self.generation else { return }
            items += page.items
            total = page.totalRecordCount ?? items.count
            error = nil
        } catch is CancellationError {
        } catch {
            guard generation == self.generation else { return }
            self.error = describe(error)
        }
    }

    /// Loads the next page when one of the last few items appears.
    func itemAppeared(_ item: BaseItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }), index >= items.count - 12 else { return }
        await loadMore()
    }

    func retry() async {
        error = nil
        await loadMore()
    }

    func apply(filter: LibraryFilter) async {
        guard filter != self.filter else { return }
        self.filter = filter
        await restart()
    }

    func apply(genreId: String?) async {
        guard genreId != self.genreId else { return }
        self.genreId = genreId
        await restart()
    }

    func apply(searchTerm: String) async {
        let trimmed = searchTerm.trimmingCharacters(in: .whitespaces)
        guard trimmed != self.searchTerm else { return }
        self.searchTerm = trimmed
        await restart()
    }

    /// After Mark watched / unwatched.
    func update(_ item: BaseItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
    }

    private func restart() async {
        generation += 1
        items = []
        total = nil
        error = nil
        isLoading = false
        await loadMore()
    }
}

/// Text under a card and in the quick look.
enum ItemLabels {
    /// "1 h 41 min", "44 min".
    static func minutes(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min" : "\(minutes) min"
    }

    /// The name on the card: the series for an episode, else the item.
    static func title(_ item: BaseItem) -> String {
        item.type == .episode ? (item.seriesName ?? item.displayName) : item.displayName
    }

    /// "S2 E4 · Woe's Hollow · 29 min left", "2025 · 1 h 41 min", "Series".
    static func detail(_ item: BaseItem) -> String {
        var parts: [String] = []
        if item.type == .episode {
            if let season = item.parentIndexNumber, let episode = item.indexNumber { parts.append("S\(season) E\(episode)") }
            else if let episode = item.indexNumber { parts.append("E\(episode)") }
            parts.append(item.displayName)
        } else {
            if let year = item.productionYear { parts.append(String(year)) }
            if item.type == .series { parts.append("Series") }
        }
        if let left = item.remainingSeconds, left > 0 {
            parts.append("\(minutes(Int((left / 60).rounded(.up)))) left")
        } else if let runtime = item.runtimeMinutes, item.type != .series {
            parts.append(minutes(runtime))
        }
        if item.type == .series, let unplayed = item.userData?.unplayedItemCount, unplayed > 0 {
            parts.append("\(unplayed) unwatched")
        }
        return parts.joined(separator: " · ")
    }

    /// The facts line of a title's page: "S1 E2 · 47 min · Drama, Sci-Fi", "2004 · 2 h 43 min · War".
    static func facts(_ item: BaseItem) -> String {
        var parts: [String] = []
        if item.type == .episode {
            if let label = item.episodeLabel { parts.append(label.replacingOccurrences(of: " · ", with: " ")) }
        } else if let year = item.productionYear {
            parts.append(String(year))
        }
        if let runtime = item.runtimeMinutes, item.type != .series { parts.append(minutes(runtime)) }
        if let genres = item.genres, !genres.isEmpty { parts.append(genres.prefix(2).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    /// "1 h 05 min left" for the hero; nil when the item is not partly watched.
    static func timeLeft(_ item: BaseItem) -> String? {
        item.remainingSeconds.map { "\(minutes(Int(($0 / 60).rounded(.up)))) left" }
    }
}

/// Text for the details view's actions.
enum PlaybackActions {
    struct Action: Equatable {
        let title: String
        let resume: Bool
    }

    static func actions(for item: BaseItem) -> [Action] {
        if let position = item.resumePositionSeconds, position > 5 {
            return [Action(title: "Resume from \(TimeFormat.clock(position))", resume: true),
                    Action(title: "Play from beginning", resume: false)]
        }
        return [Action(title: "Play", resume: false)]
    }
}
