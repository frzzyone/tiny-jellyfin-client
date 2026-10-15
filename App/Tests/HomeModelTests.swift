import JellyfinKit
import XCTest
@testable import TinyJellyfin

@MainActor
final class HomeModelTests: XCTestCase {
    let today = Date(timeIntervalSince1970: 1_791_800_000) // 2026-10-12
    var service: FakeLibraryService!

    override func setUp() {
        service = FakeLibraryService()
    }

    func makeModel(day: Date? = nil) -> HomeModel {
        let now = day ?? today
        return HomeModel(service: service, now: { now })
    }

    func testRotationShowsThreeOfFiveAndIsStableWithinADay() {
        let a = DiscoveryKind.rotation(day: 20739)
        XCTAssertEqual(a.count, 3)
        XCTAssertEqual(Set(a).count, 3)
        XCTAssertEqual(a, DiscoveryKind.rotation(day: 20739))
        XCTAssertNotEqual(a, DiscoveryKind.rotation(day: 20740))
        XCTAssertEqual(DiscoveryKind.rotation(day: 5), DiscoveryKind.rotation(day: 10), "five-day cycle")
    }

    func testLibraryTabsGetTwoRowsThatSuitThemAndHomeIsNotShowing() {
        for day in 0..<5 {
            let home = Set(DiscoveryKind.rotation(day: day))
            let films = DiscoveryKind.forLibrary(day: day, shows: false)
            let shows = DiscoveryKind.forLibrary(day: day, shows: true)
            XCTAssertEqual(films.count, 2)
            XCTAssertEqual(shows.count, 2)
            XCTAssertFalse(films.contains(.almostDone), "a film library has no series")
            XCTAssertFalse(shows.contains(.shortTonight) || shows.contains(.becauseYouWatched))
            // A kind that suits the library and isn't on Home today comes first.
            let filmKinds: Set<DiscoveryKind> = [.shortTonight, .becauseYouWatched, .shelf, .decade]
            if !filmKinds.subtracting(home).isEmpty { XCTAssertFalse(home.contains(films[0]), "day \(day)") }
            XCTAssertEqual(films, DiscoveryKind.forLibrary(day: day, shows: false), "stable within a day")
        }
    }

    func testLibraryRowsStayInsideTheLibrary() async {
        var library = item("films", type: .collectionFolder)
        library.collectionType = "movies"
        service.onItems = { _ in [item("a", minutes: 90)] }
        service.resume = [item("troy", position: 100)]
        let model = HomeModel(service: service, library: library, now: { self.today })
        await model.load()
        XCTAssertNil(model.hero, "no hero in a library tab")
        XCTAssertEqual(model.rows.map(\.id), DiscoveryKind.forLibrary(day: HomeRules.dayNumber(today), shows: false).map(\.rawValue))
        XCTAssertFalse(service.queries.isEmpty)
        XCTAssertTrue(service.queries.allSatisfy { $0.parentId == "films" }, "\(service.queries.map(\.parentId))")
        XCTAssertTrue(service.queries.allSatisfy { $0.types == [.movie] })
    }

    func testPlannedRowsOrder() {
        let ids = makeModel().plannedRows.map(\.id)
        XCTAssertEqual(ids.prefix(3), ["continue", "nextUp", "latest"])
        XCTAssertEqual(ids.last, "genre")
        XCTAssertEqual(ids.count, 7)
    }

    func testEmptyLibrary() async {
        let model = makeModel()
        XCTAssertFalse(model.isEmpty, "not before loading")
        await model.load()
        XCTAssertTrue(model.isEmpty)
        service.latestItems = [item("new", created: "2026-10-11T10:00:00.0000000Z")]
        await model.load()
        XCTAssertFalse(model.isEmpty)
    }

    func testHeroIsTheLastWatchedAndRestIsTheRow() async {
        service.resume = [item("troy", position: 100), item("sam", position: 50)]
        let model = makeModel()
        await model.load()
        XCTAssertEqual(model.hero?.id, "troy")
        XCTAssertEqual(model.rows.first { $0.id == "continue" }?.items.map(\.id), ["sam"])
    }

    func testHeroFallsBackToNextUpThenLatest() async {
        service.nextUpItems = [item("e4", type: .episode)]
        var model = makeModel()
        await model.load()
        XCTAssertEqual(model.hero?.id, "e4")
        service.nextUpItems = []
        service.latestItems = [item("new", created: "2026-10-11T08:00:00.0000000Z")]
        model = makeModel()
        await model.load()
        XCTAssertEqual(model.hero?.id, "new")
    }

    func testHeroIsNotRepeatedInTheRows() async {
        service.resume = [item("e2", type: .episode, position: 100)]
        service.nextUpItems = [item("e2", type: .episode), item("e9", type: .episode)]
        let model = makeModel()
        await model.load()
        XCTAssertEqual(model.hero?.id, "e2")
        XCTAssertEqual(model.visibleRows.first { $0.id == "nextUp" }?.items.map(\.id), ["e9"])
    }

    func testEmptyRowsAreHiddenAndErrorsStay() async {
        service.errors = ["nextUp"]
        service.resume = [item("troy", position: 100)]
        let model = makeModel()
        await model.load()
        let visible = model.visibleRows.map(\.id)
        XCTAssertFalse(visible.contains("continue"), "only the hero was in progress")
        XCTAssertFalse(visible.contains("latest"))
        XCTAssertTrue(visible.contains("nextUp"), "a failed row stays, with its error")
        XCTAssertNotNil(model.rows.first { $0.id == "nextUp" }?.error)
    }

    func testAddedThisWeekKeepsOnlyTheLastSevenDays() async {
        service.latestItems = [item("fresh", created: "2026-10-10T08:00:00.0000000Z"),
                               item("old", created: "2026-09-20T08:00:00.0000000Z"),
                               item("undated")]
        let model = makeModel()
        await model.load()
        XCTAssertEqual(model.rows.first { $0.id == "latest" }?.items.map(\.id), ["fresh"])
    }

    func testRules() {
        XCTAssertTrue(HomeRules.isShort(item("a", minutes: 99)))
        XCTAssertFalse(HomeRules.isShort(item("b", minutes: 100)))
        XCTAssertFalse(HomeRules.isShort(item("c")))
        XCTAssertTrue(HomeRules.isAlmostDone(item("s", type: .series, unplayed: 2, lastPlayed: "2026-10-01T00:00:00Z")))
        XCTAssertFalse(HomeRules.isAlmostDone(item("t", type: .series, unplayed: 3, lastPlayed: "2026-10-01T00:00:00Z")))
        XCTAssertFalse(HomeRules.isAlmostDone(item("u", type: .series, unplayed: 1)), "never started")
        XCTAssertEqual(HomeRules.decade(day: 0, earliestYear: 1975, now: today), 1970)
        XCTAssertEqual(HomeRules.decade(day: 1, earliestYear: 1975, now: today), 1980)
        XCTAssertEqual(HomeRules.decade(day: 6, earliestYear: 1975, now: today), 1970, "six decades, wraps")
        XCTAssertEqual(HomeRules.decade(day: 3, earliestYear: 2030, now: today), 2020, "never past today")
        XCTAssertNotNil(HomeRules.parse("2026-10-10T08:00:00.0000000Z"))
        XCTAssertNotNil(HomeRules.parse("2026-10-10T08:00:00Z"))
    }

    func testShortTonightFiltersByRuntimeAfterARandomQuery() async {
        // Pick a day whose rotation includes Short tonight.
        let day = (0...6).first { DiscoveryKind.rotation(day: HomeRules.dayNumber(today) + $0).contains(.shortTonight) }!
        let now = today.addingTimeInterval(Double(day) * 86_400)
        service.onItems = { query in
            guard query.sort == .random, query.filters == [.unplayed], query.types == [.movie] else { return [] }
            return [item("short", minutes: 85), item("long", minutes: 150), item("ok", minutes: 99)]
        }
        let model = makeModel(day: now)
        await model.load()
        XCTAssertEqual(model.rows.first { $0.id == "shortTonight" }?.items.map(\.id), ["short", "ok"])
    }

    func testBecauseYouWatchedNamesTheFilm() async {
        let day = (0...6).first { DiscoveryKind.rotation(day: HomeRules.dayNumber(today) + $0).contains(.becauseYouWatched) }!
        let now = today.addingTimeInterval(Double(day) * 86_400)
        service.onItems = { query in query.sort == .datePlayed ? [item("heat")] : [] }
        service.similarItems = [item("collateral")]
        let model = makeModel(day: now)
        await model.load()
        let row = model.rows.first { $0.id == "becauseYouWatched" }
        XCTAssertEqual(row?.title, "Because you watched Heat")
        XCTAssertEqual(row?.items.map(\.id), ["collateral"])
    }

    func testAlmostDoneUsesNextUpPerSeries() async {
        let day = (0...6).first { DiscoveryKind.rotation(day: HomeRules.dayNumber(today) + $0).contains(.almostDone) }!
        let now = today.addingTimeInterval(Double(day) * 86_400)
        service.onItems = { query in
            query.types == [.series] ? [item("slow", type: .series, unplayed: 1, lastPlayed: "2026-10-01T00:00:00Z"),
                                        item("bear", type: .series, unplayed: 6, lastPlayed: "2026-10-01T00:00:00Z")] : []
        }
        service.nextUpBySeries = ["slow": [item("slow-e6", type: .episode)]]
        let model = makeModel(day: now)
        await model.load()
        XCTAssertEqual(model.rows.first { $0.id == "almostDone" }?.items.map(\.id), ["slow-e6"])
    }

    func testGenreRowSwitchesInPlace() async {
        service.genreList = [NameGuidPair(id: "g1", name: "Thriller"), NameGuidPair(id: "g2", name: "Animation")]
        service.onItems = { query in
            switch query.genreIds.first {
            case "g1": [item("prisoners")]
            case "g2": [item("spirited")]
            default: []
            }
        }
        let model = makeModel()
        await model.load()
        var row = model.rows.first { $0.id == "genre" }
        XCTAssertEqual(row?.title, "Tonight, a thriller")
        XCTAssertEqual(row?.items.map(\.id), ["prisoners"])
        await model.selectGenre("g2")
        row = model.rows.first { $0.id == "genre" }
        XCTAssertEqual(row?.genreId, "g2")
        XCTAssertEqual(row?.items.map(\.id), ["spirited"])
        XCTAssertEqual(HomeModel.article("Animation"), "an animation")
    }

    func testSurpriseAsksForOneRandomUnwatchedFilm() async throws {
        service.onItems = { query in
            query.sort == .random && query.limit == 1 && query.filters == [.unplayed] ? [item("lucky")] : []
        }
        let pick = try await makeModel().surprise()
        XCTAssertEqual(pick?.id, "lucky")
    }

    func testRefreshProgressReloadsOnlyTheProgressRows() async {
        service.resume = [item("troy", position: 100)]
        service.nextUpItems = [item("e4", type: .episode)]
        service.onItems = { query in query.sort == .dateCreated && query.filters == [.unplayed] ? [item("shelf1")] : [] }
        let day = (0...6).first { DiscoveryKind.rotation(day: HomeRules.dayNumber(today) + $0).contains(.shelf) }!
        let model = makeModel(day: today.addingTimeInterval(Double(day) * 86_400))
        await model.load()
        XCTAssertEqual(model.hero?.id, "troy")
        service.resume = [item("sam", position: 50), item("troy", position: 100)]
        service.nextUpItems = [item("e5", type: .episode)]
        service.onItems = { _ in [item("shelf2")] }
        await model.refreshProgress()
        XCTAssertEqual(model.hero?.id, "sam")
        XCTAssertEqual(model.rows.first { $0.id == "continue" }?.items.map(\.id), ["troy"])
        XCTAssertEqual(model.rows.first { $0.id == "nextUp" }?.items.map(\.id), ["e5"])
        XCTAssertEqual(model.rows.first { $0.id == "shelf" }?.items.map(\.id), ["shelf1"], "untouched")
    }

    func testUpdateReplacesTheItemEverywhere() async {
        service.resume = [item("troy", position: 100), item("sam", position: 50)]
        let model = makeModel()
        await model.load()
        var watched = item("sam")
        watched.userData = UserItemData(played: true)
        model.update(watched)
        XCTAssertEqual(model.rows.first { $0.id == "continue" }?.items.first?.userData?.played, true)
    }

    func testLabels() {
        XCTAssertEqual(ItemLabels.minutes(101), "1 h 41 min")
        XCTAssertEqual(ItemLabels.minutes(44), "44 min")
        var episode = item("woe", type: .episode, minutes: 50, position: 21 * 60)
        episode.seriesName = "Severance"; episode.parentIndexNumber = 2; episode.indexNumber = 4; episode.name = "Woe's Hollow"
        XCTAssertEqual(ItemLabels.title(episode), "Severance")
        XCTAssertEqual(ItemLabels.detail(episode), "S2 E4 · Woe's Hollow · 29 min left")
        XCTAssertEqual(ItemLabels.detail(item("film", minutes: 101, year: 2025)), "2025 · 1 h 41 min")
        XCTAssertEqual(ItemLabels.detail(item("show", type: .series, year: 2024, unplayed: 3)), "2024 · Series · 3 unwatched")
        XCTAssertEqual(ItemLabels.timeLeft(item("troy", minutes: 196, position: 131 * 60)), "1 h 05 min left")
        XCTAssertNil(ItemLabels.timeLeft(item("new", minutes: 90)))

        // The player's line: the end is the clock time at the current speed.
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let end = { (seconds: Double) in now.addingTimeInterval(seconds).formatted(date: .omitted, time: .shortened) }
        XCTAssertEqual(ItemLabels.playing(episode, remaining: 600, speed: 1, now: now), "S2 E4 · Woe's Hollow · ends \(end(600))")
        XCTAssertEqual(ItemLabels.playing(item("avatar", year: 2009), remaining: 3600, speed: 2, now: now), "2009 · ends \(end(1800))")
        XCTAssertEqual(ItemLabels.playing(item("avatar", year: 2009), remaining: 0, speed: 1, now: now), "2009", "no end while the length is unknown")
    }
}
