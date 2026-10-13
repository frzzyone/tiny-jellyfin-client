import JellyfinKit
import XCTest
@testable import TinyJellyfin

@MainActor
final class SeriesModelTests: XCTestCase {
    var service: FakeLibraryService!

    override func setUp() {
        service = FakeLibraryService()
        service.seasonList = [item("s1", type: .season), item("s2", type: .season)]
        service.episodesBySeason = ["s1": [item("e1", type: .episode), item("e2", type: .episode)],
                                    "s2": [item("e3", type: .episode)]]
    }

    func testOpensOnTheSeasonOfTheNextEpisode() async {
        var next = item("e3", type: .episode)
        next.seasonId = "s2"
        service.nextUpBySeries["show"] = [next]
        let model = SeriesModel(series: item("show", type: .series), service: service)
        await model.load()
        XCTAssertEqual(model.season?.id, "s2")
        XCTAssertEqual(model.episodes.map(\.id), ["e3"])
        XCTAssertEqual(model.nextUp?.id, "e3")
    }

    func testWithoutNextUpPlaysTheFirstEpisode() async {
        let model = SeriesModel(series: item("show", type: .series), service: service)
        await model.load()
        XCTAssertEqual(model.season?.id, "s1")
        XCTAssertEqual(model.nextUp?.id, "e1")
        await model.select(service.seasonList[1])
        XCTAssertEqual(model.episodes.map(\.id), ["e3"])
        XCTAssertEqual(model.nextUp?.id, "e1", "picking a season doesn't change what Resume plays")
    }

    func testError() async {
        service.errors = ["seasons"]
        let model = SeriesModel(series: item("show", type: .series), service: service)
        await model.load()
        XCTAssertNotNil(model.error)
    }
}
