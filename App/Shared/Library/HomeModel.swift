import Foundation
import JellyfinKit
import Observation

/// How a row draws its items: 2:3 posters, or 16:9 stills (episodes, things in progress).
enum RowShape { case poster, still }

/// One row of Home. `items` is empty while loading or when there is nothing to show.
struct HomeRow: Identifiable, Equatable {
    let id: String
    var title: String
    var subtitle: String?
    var shape: RowShape
    var items: [BaseItem] = []
    var error: String?
    /// The genre row only: the genres to switch between and the one shown.
    var genres: [NameGuidPair] = []
    var genreId: String?

    var isEmpty: Bool { items.isEmpty && error == nil }
}

/// The rows that find something without typing. Each is one query; see `HomeModel`.
enum DiscoveryKind: String, CaseIterable {
    case shortTonight, becauseYouWatched, almostDone, shelf, decade

    /// Three of the five, rotating daily so the page changes without becoming random.
    static func rotation(day: Int) -> [DiscoveryKind] {
        Array(order(day: day).prefix(3))
    }

    /// Today's rows for one library tab: two that suit it (films or series), the ones Home isn't
    /// showing today first, so the tab adds to Home rather than repeating it.
    static func forLibrary(day: Int, shows: Bool) -> [DiscoveryKind] {
        let suits: Set<DiscoveryKind> = shows ? [.almostDone, .shelf, .decade] : [.shortTonight, .becauseYouWatched, .shelf, .decade]
        let today = order(day: day)
        let onHome = Set(rotation(day: day))
        return Array((today.filter { !onHome.contains($0) } + today.filter(onHome.contains)).filter(suits.contains).prefix(2))
    }

    private static func order(day: Int) -> [DiscoveryKind] {
        let all = allCases
        let offset = ((day % all.count) + all.count) % all.count
        return (0..<all.count).map { all[(offset + $0) % all.count] }
    }
}

enum HomeRules {
    static let shortMinutes = 100
    static let recentDays = 7
    static let almostDoneRange = 1...2

    static func isShort(_ item: BaseItem) -> Bool {
        guard let minutes = item.runtimeMinutes else { return false }
        return minutes < shortMinutes
    }

    static func isRecent(_ item: BaseItem, now: Date) -> Bool {
        guard let created = item.dateCreated.flatMap(Self.parse) else { return false }
        return now.timeIntervalSince(created) <= Double(recentDays) * 86_400
    }

    /// A series the user has started that has one or two episodes left.
    static func isAlmostDone(_ series: BaseItem) -> Bool {
        guard let left = series.userData?.unplayedItemCount, almostDoneRange.contains(left) else { return false }
        return series.userData?.lastPlayedDate != nil || (series.userData?.playedPercentage ?? 0) > 0
    }

    /// The decade to show today, from the oldest year in the library to the current one.
    static func decade(day: Int, earliestYear: Int, now: Date) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let thisDecade = (calendar.component(.year, from: now) / 10) * 10
        let first = min((earliestYear / 10) * 10, thisDecade)
        let count = (thisDecade - first) / 10 + 1
        return first + 10 * (((day % count) + count) % count)
    }

    static func dayNumber(_ now: Date) -> Int { Int(now.timeIntervalSince1970 / 86_400) }

    static func parse(_ iso: String) -> Date? {
        // Jellyfin writes seven fractional digits; ISO8601DateFormatter wants at most three.
        let trimmed = iso.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: trimmed) ?? ISO8601DateFormatter().date(from: trimmed)
    }
}

/// Home: the hero, the fixed rows, and today's discovery rows, each loaded on its own. Given a
/// library, it is that tab's discovery rows instead (`DiscoveryKind.forLibrary`), drawn from it alone.
@MainActor
@Observable
final class HomeModel {
    private(set) var hero: BaseItem?
    private(set) var heroError: String?
    private(set) var rows: [HomeRow] = []
    private(set) var isLoading = false
    @ObservationIgnored private let service: LibraryService
    @ObservationIgnored private let now: () -> Date
    /// A library tab's rows rather than Home's.
    @ObservationIgnored private let library: (id: String, shows: Bool)?

    static let continueID = "continue", nextUpID = "nextUp", latestID = "latest", genreID = "genre"

    init(service: LibraryService, library: BaseItem? = nil, now: @escaping () -> Date = Date.init) {
        self.service = service
        self.library = library.map { ($0.id, $0.collectionType?.lowercased() == "tvshows") }
        self.now = now
    }

    /// Rows this page shows, in order, before anything is loaded.
    var plannedRows: [HomeRow] {
        let day = HomeRules.dayNumber(now())
        if let library { return DiscoveryKind.forLibrary(day: day, shows: library.shows).map(Self.row) }
        return [
            HomeRow(id: Self.continueID, title: "Continue watching", shape: .still),
            HomeRow(id: Self.nextUpID, title: "Next up", subtitle: "the next episode of every series you're into", shape: .still),
            HomeRow(id: Self.latestID, title: "Added this week", shape: .poster),
        ] + DiscoveryKind.rotation(day: day).map(Self.row)
            + [HomeRow(id: Self.genreID, title: "Tonight, a genre", subtitle: "unwatched only", shape: .poster)]
    }

    private static func row(_ kind: DiscoveryKind) -> HomeRow {
        switch kind {
        case .shortTonight:
            HomeRow(id: kind.rawValue, title: "Short tonight", subtitle: "unwatched, under \(HomeRules.shortMinutes) minutes", shape: .poster)
        case .becauseYouWatched:
            HomeRow(id: kind.rawValue, title: "Because you watched", shape: .poster)
        case .almostDone:
            HomeRow(id: kind.rawValue, title: "Almost done", subtitle: "series with one or two episodes left", shape: .still)
        case .shelf:
            HomeRow(id: kind.rawValue, title: "Been on the shelf a while", subtitle: "the oldest things you added and never played", shape: .poster)
        case .decade:
            HomeRow(id: kind.rawValue, title: "From the decade", subtitle: "a different decade each day", shape: .poster)
        }
    }

    /// Rows with something in them (or an error to show), in planned order, without the hero:
    /// it is already at the top, and Next up often holds the same episode.
    var visibleRows: [HomeRow] {
        rows.map { row in
            var row = row
            row.items.removeAll { $0.id == hero?.id }
            return row
        }
        .filter { !$0.isEmpty }
    }

    /// Loaded, and the server had nothing for any row: an empty or unreadable library.
    var isEmpty: Bool { !isLoading && !rows.isEmpty && hero == nil && heroError == nil && visibleRows.isEmpty }

    static let emptyMessage = "Nothing to show yet. Add films or series to a Jellyfin library this account can see."

    func load() async {
        isLoading = true
        rows = plannedRows
        await withTaskGroup(of: Void.self) { group in
            if library == nil { group.addTask { await self.loadHeroAndContinue() } }
            for row in rows where row.id != Self.continueID {
                group.addTask { await self.load(rowID: row.id) }
            }
        }
        isLoading = false
    }

    private func loadHeroAndContinue() async {
        do {
            let items = try await service.resumeItems()
            hero = items.first
            heroError = nil
            set(Self.continueID, items: Array(items.dropFirst()))
        } catch is CancellationError {
        } catch {
            heroError = describe(error)
            set(Self.continueID, error: describe(error))
        }
        // Nothing in progress: lead with the next episode, or the newest title.
        if hero == nil {
            if let next = try? await service.nextUp(limit: 1, seriesId: nil).first {
                hero = next
            } else if let newest = try? await service.latest(limit: 1).first {
                hero = newest
            }
        }
    }

    private func load(rowID: String) async {
        do {
            let (items, subtitle) = try await fetch(rowID: rowID)
            set(rowID, items: items, subtitle: subtitle)
        } catch is CancellationError {
        } catch {
            set(rowID, error: describe(error))
        }
    }

    private func fetch(rowID: String) async throws -> ([BaseItem], String?) {
        // In a library tab every query stays inside it, and asks for what that library holds.
        let parentId = library?.id
        let titles: [ItemKind] = library.map { $0.shows ? [.series] : [.movie] } ?? [.movie]
        switch rowID {
        case Self.nextUpID:
            return (try await service.nextUp(limit: 24, seriesId: nil), nil)
        case Self.latestID:
            let now = now()
            return (try await service.latest(limit: 24).filter { HomeRules.isRecent($0, now: now) }, nil)
        case DiscoveryKind.shortTonight.rawValue:
            let query = ItemQuery(parentId: parentId, types: [.movie], filters: [.unplayed], sort: .random, limit: 60)
            let items = try await service.items(query).items.filter(HomeRules.isShort)
            return (Array(items.prefix(24)), nil)
        case DiscoveryKind.becauseYouWatched.rawValue:
            let last = ItemQuery(parentId: parentId, types: [.movie], filters: [.played], sort: .datePlayed, descending: true, limit: 1)
            guard let watched = try await service.items(last).items.first else { return ([], nil) }
            let similar = try await service.similar(to: watched.id, limit: 24)
            return (similar, "because you watched \(watched.displayName)")
        case DiscoveryKind.almostDone.rawValue:
            let recent = ItemQuery(parentId: parentId, types: [.series], sort: .datePlayed, descending: true, limit: 50)
            let series = try await service.items(recent).items.filter(HomeRules.isAlmostDone).prefix(8)
            var episodes: [BaseItem] = []
            for show in series {
                if let next = try await service.nextUp(limit: 1, seriesId: show.id).first { episodes.append(next) }
            }
            return (episodes, nil)
        case DiscoveryKind.shelf.rawValue:
            let query = ItemQuery(parentId: parentId, types: library == nil ? [.movie, .series] : titles,
                                  filters: [.unplayed], sort: .dateCreated, limit: 24)
            return (try await service.items(query).items, nil)
        case DiscoveryKind.decade.rawValue:
            let oldest = ItemQuery(parentId: parentId, types: titles, sort: .premiereDate, limit: 1)
            guard let earliest = try await service.items(oldest).items.first?.productionYear else { return ([], nil) }
            let decade = HomeRules.decade(day: HomeRules.dayNumber(now()), earliestYear: earliest, now: now())
            var query = ItemQuery(parentId: parentId, types: titles, sort: .random, limit: 24)
            query.years = Array(decade...(decade + 9))
            return (try await service.items(query).items, "From the \(decade)s")
        case Self.genreID:
            let genres = try await service.genres(libraryId: nil)
            guard let genre = genres.first else { return ([], nil) }
            replaceGenres(genres, selected: genre.id)
            return (try await genreItems(genre.id), nil)
        default:
            return ([], nil)
        }
    }

    private func genreItems(_ genreId: String) async throws -> [BaseItem] {
        var query = ItemQuery(types: [.movie, .series], filters: [.unplayed], sort: .random, limit: 24)
        query.genreIds = [genreId]
        return try await service.items(query).items
    }

    /// After playback: the hero, Continue watching and Next up follow the server's new positions;
    /// the other rows stay as they are so the page does not reshuffle.
    func refreshProgress() async {
        guard !rows.isEmpty, library == nil else { return }
        async let resume: Void = loadHeroAndContinue()
        async let next: Void = load(rowID: Self.nextUpID)
        _ = await (resume, next)
    }

    /// Switches the genre row in place.
    func selectGenre(_ genreId: String) async {
        guard let index = rows.firstIndex(where: { $0.id == Self.genreID }) else { return }
        rows[index].genreId = genreId
        do {
            let items = try await genreItems(genreId)
            guard rows.indices.contains(index), rows[index].genreId == genreId else { return }
            rows[index].items = items
            rows[index].error = nil
        } catch is CancellationError {
        } catch {
            rows[index].error = describe(error)
        }
    }

    /// One random film the user has not watched.
    func surprise() async throws -> BaseItem? {
        try await service.items(ItemQuery(types: [.movie], filters: [.unplayed], sort: .random, limit: 1)).items.first
    }

    /// After Mark watched / unwatched: the card shows the new state at once.
    func update(_ item: BaseItem) {
        if hero?.id == item.id { hero = item }
        for index in rows.indices {
            if let i = rows[index].items.firstIndex(where: { $0.id == item.id }) { rows[index].items[i] = item }
        }
    }

    private func set(_ rowID: String, items: [BaseItem] = [], error: String? = nil, subtitle: String? = nil) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[index].items = items
        rows[index].error = error
        if rowID == DiscoveryKind.decade.rawValue, let subtitle { rows[index].title = subtitle }
        else if let subtitle, rowID == DiscoveryKind.becauseYouWatched.rawValue { rows[index].title = subtitle.prefix(1).uppercased() + subtitle.dropFirst() }
    }

    private func replaceGenres(_ genres: [NameGuidPair], selected: String) {
        guard let index = rows.firstIndex(where: { $0.id == Self.genreID }) else { return }
        rows[index].genres = genres
        rows[index].genreId = selected
        rows[index].title = "Tonight, " + (genres.first { $0.id == selected }?.name.map(Self.article) ?? "a genre")
    }

    static func article(_ genre: String) -> String {
        let lower = genre.lowercased()
        return ("aeiou".contains(lower.first ?? " ") ? "an " : "a ") + lower
    }
}
