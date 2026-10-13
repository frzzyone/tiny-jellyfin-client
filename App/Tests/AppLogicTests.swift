import JellyfinKit
import PlayerCore
import XCTest
@testable import TinyJellyfin

@MainActor
final class AppLogicTests: XCTestCase {
    /// FFmpeg's LGPL needs its notice and licence text inside the app (shown under Acknowledgements).
    func testLicencesShipInTheApp() throws {
        for name in ["THIRD_PARTY_NOTICES.md", "BUILD-INFO", "COPYING.LGPLv2.1"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: nil), name)
            XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).isEmpty, name)
        }
    }

    func testSubtitlePictureRectLetterboxAndPillarbox() {
        let screen = CGSize(width: 1920, height: 1080)
        let scope = SubtitleLayout.pictureRect(video: CGSize(width: 2390, height: 1000), in: screen)
        XCTAssertEqual(scope.width, 1920, accuracy: 0.01)
        XCTAssertEqual(scope.height, 803.35, accuracy: 0.01, "2.39:1 film fills the width")
        XCTAssertEqual(scope.minY, 138.33, accuracy: 0.01, "centred between the bars")
        XCTAssertEqual(scope.minX, 0, accuracy: 0.01)
        let tv = SubtitleLayout.pictureRect(video: CGSize(width: 640, height: 480), in: screen)
        XCTAssertEqual(tv.height, 1080, accuracy: 0.01, "4:3 fills the height")
        XCTAssertEqual(tv.width, 1440, accuracy: 0.01)
        XCTAssertEqual(tv.minX, 240, accuracy: 0.01)
        XCTAssertEqual(SubtitleLayout.pictureRect(video: CGSize(width: 1920, height: 1080), in: screen),
                       CGRect(origin: .zero, size: screen), "exact fit")
        XCTAssertEqual(SubtitleLayout.pictureRect(video: nil, in: screen), CGRect(origin: .zero, size: screen),
                       "unknown video size uses the whole view")
        XCTAssertEqual(SubtitleLayout.pictureRect(video: .zero, in: screen), CGRect(origin: .zero, size: screen))
    }

    func testSubtitlePictureRectExcludesBarsInTheFrame() {
        let screen = CGSize(width: 1920, height: 1080)
        let bars = PictureBars(top: 0.128, bottom: 0.128)
        let rect = SubtitleLayout.pictureRect(video: CGSize(width: 1920, height: 1080), in: screen, bars: bars)
        XCTAssertEqual(rect.minY, 138.24, accuracy: 0.01)
        XCTAssertEqual(rect.height, 803.52, accuracy: 0.01)
        XCTAssertEqual(rect.width, 1920)
        let windowed = SubtitleLayout.pictureRect(video: CGSize(width: 1920, height: 1080), in: CGSize(width: 1280, height: 720), bars: bars)
        XCTAssertEqual(windowed.minY, 92.16, accuracy: 0.01, "bars scale with the picture")
        XCTAssertEqual(windowed.maxY, 720 - 92.16, accuracy: 0.01)
    }

    func testStreamLogHidesTheToken() {
        let url = URL(string: "https://j.test/videos/x/master.m3u8?DeviceId=d&ApiKey=secret&MediaSourceId=m&api_key=also")!
        XCTAssertEqual(PlaybackController.redactedQuery(url), "DeviceId=d&ApiKey=…&MediaSourceId=m&api_key=…")
    }

    func testTopShelfLinks() {
        let play = TopShelfLink(itemId: "abc123", play: true)
        XCTAssertEqual(play.url.absoluteString, "tinyjellyfin://play/abc123")
        XCTAssertEqual(TopShelfLink(url: play.url), play)
        XCTAssertEqual(TopShelfLink(url: URL(string: "tinyjellyfin://item/abc123")!), TopShelfLink(itemId: "abc123", play: false))
        XCTAssertNil(TopShelfLink(url: URL(string: "tinyjellyfin://item/")!))
        XCTAssertNil(TopShelfLink(url: URL(string: "tinyjellyfin://delete/abc")!))
        XCTAssertNil(TopShelfLink(url: URL(string: "https://item/abc")!))
    }

    func testSwipeScrub() {
        XCTAssertEqual(SwipeScrub.target(start: 3000, fraction: 1, duration: 7200), 3600, "two hours: a full swipe is 10 min")
        XCTAssertEqual(SwipeScrub.target(start: 1000, fraction: 0.5, duration: 3000), 1150, "50 min: a tenth")
        XCTAssertEqual(SwipeScrub.target(start: 100, fraction: -1, duration: 300), 40, "short: at least a minute")
        XCTAssertEqual(SwipeScrub.target(start: 10, fraction: -1, duration: 3000), 0, "not before the start")
        XCTAssertEqual(SwipeScrub.target(start: 2990, fraction: 1, duration: 3000), 3000, "not past the end")
    }

    func testControlsWaitForAnOpenMenu() {
        XCTAssertTrue(ControlsAutoHide.due(playing: true, scrubbing: false, menuOpen: false, idle: 3))
        XCTAssertFalse(ControlsAutoHide.due(playing: true, scrubbing: false, menuOpen: true, idle: 600), "a menu stays until closed")
        XCTAssertFalse(ControlsAutoHide.due(playing: true, scrubbing: true, menuOpen: false, idle: 10))
        XCTAssertFalse(ControlsAutoHide.due(playing: false, scrubbing: false, menuOpen: false, idle: 10), "paused or loading")
        XCTAssertFalse(ControlsAutoHide.due(playing: true, scrubbing: false, menuOpen: false, idle: 2.9))
    }

    func testTrackpadStrokesChain() {
        var first = TrackpadScrub(start: 3000)
        first.travel = 1600
        let aimed = first.target(duration: 7200)
        XCTAssertEqual(aimed, 4200, "a long stroke on a two-hour film: 20 min")
        var second = TrackpadScrub(start: aimed) // the next stroke starts where the last one aimed
        second.travel = 1600
        XCTAssertEqual(second.target(duration: 7200), 5400)
        var back = TrackpadScrub(start: 5400)
        back.travel = -400
        XCTAssertEqual(back.target(duration: 7200), 5100)
    }

    func testHoldPlaysAt2xAndGoesBack() {
        var hold = SpeedHold()
        XCTAssertEqual(hold.begin(from: 1.25), 2)
        XCTAssertEqual(hold.begin(from: 2), 2, "a second begin while held keeps the first speed to go back to")
        XCTAssertTrue(hold.isHolding)
        XCTAssertEqual(hold.end(), 1.25)
        XCTAssertNil(hold.end(), "only once")
        XCTAssertFalse(hold.isHolding)
    }

    func testSwipeLevel() {
        XCTAssertEqual(SwipeLevel.adjusted(start: 0.5, translation: -100, height: 400), 0.8125, accuracy: 0.0001, "up raises")
        XCTAssertEqual(SwipeLevel.adjusted(start: 0.5, translation: 100, height: 400), 0.1875, accuracy: 0.0001, "down lowers")
        XCTAssertEqual(SwipeLevel.adjusted(start: 0.9, translation: -400, height: 400), 1, "clamped at the top")
        XCTAssertEqual(SwipeLevel.adjusted(start: 0.1, translation: 400, height: 400), 0, "clamped at the bottom")
        XCTAssertEqual(SwipeLevel.adjusted(start: 0.4, translation: 50, height: 0), 0.4)
    }

    func testSubtitleFontScalesWithThePicture() {
        XCTAssertEqual(CTFontGetSize(SubtitleFont.font(forPictureHeight: 1080)), 48)
        XCTAssertEqual(CTFontCopyPostScriptName(SubtitleFont.font(forPictureHeight: 1080)) as String, "HelveticaNeue")
        XCTAssertEqual(CTFontGetSize(SubtitleFont.font(forPictureHeight: 540)), 24)
        XCTAssertEqual(CTFontGetSize(SubtitleFont.font(forPictureHeight: 100)), 12, "never smaller than 12 pt")
    }

    func testLoaderErrorStateAndRetry() async {
        var attempts = 0
        let loader = Loader<Int> {
            attempts += 1
            if attempts == 1 { throw JellyfinError.network("offline") }
            return 42
        }
        await loader.load()
        guard case .failed(let message) = loader.state else { return XCTFail("\(loader.state)") }
        XCTAssertTrue(message.contains("could not be reached"))
        await loader.load()
        XCTAssertEqual(loader.state.value, 42)
    }

    func testGridPaging() async {
        let all = (0..<130).map { BaseItem(id: "i\($0)", name: "Item \($0)", type: .movie) }
        let grid = LibraryGridModel(parentId: "lib") { query in
            let start = query.startIndex, limit = query.limit
            return ItemsResult(items: Array(all[start..<min(all.count, start + limit)]), totalRecordCount: all.count, startIndex: start)
        }
        await grid.loadMore()
        XCTAssertEqual(grid.items.count, 60)
        await grid.itemAppeared(grid.items[10])
        XCTAssertEqual(grid.items.count, 60, "early items don't trigger paging")
        await grid.itemAppeared(grid.items[55])
        XCTAssertEqual(grid.items.count, 120)
        await grid.loadMore()
        XCTAssertEqual(grid.items.count, 130)
        XCTAssertFalse(grid.hasMore)
    }

    func testCapabilitiesMapping() {
        let caps = PlaybackCapabilities(EngineCapabilities(av1: true, hevc: true, hdr: true, dolbyVision: false))
        XCTAssertTrue(caps.av1)
        XCTAssertTrue(caps.hevc10Bit)
        XCTAssertFalse(caps.dolbyVision)
        let profile = DeviceProfileBuilder.build(capabilities: caps, quality: .original)
        XCTAssertEqual(profile.directPlayProfiles[0].videoCodec, "h264,hevc,av1")
    }

    func testSubtitleOptionsLabels() {
        let options = PlaybackController.subtitleOptions(movie().mediaSources![0])
        XCTAssertEqual(options.map(\.label), ["English", "Spanish", "French · External"])
        XCTAssertEqual(options.map(\.isImage), [false, true, false])
    }

    func testKeychainStoresOnlyTokens() throws {
        let store = KeychainTokenStore()
        let account = "test-\(UUID().uuidString)"
        do {
            try store.setToken("abc", account: account)
        } catch {
            throw XCTSkip("Keychain unavailable on this runner: \(error)")
        }
        XCTAssertEqual(try store.token(account: account), "abc")
        try store.setToken("def", account: account)
        XCTAssertEqual(try store.token(account: account), "def")
        try store.deleteToken(account: account)
        XCTAssertNil(try store.token(account: account))
    }
}
