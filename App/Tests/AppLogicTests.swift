import JellyfinKit
import PlayerCore
import XCTest
@testable import TinyJellyfin

@MainActor
final class AppLogicTests: XCTestCase {
    func testPlaybackActionsForPartlyWatchedItem() {
        let actions = PlaybackActions.actions(for: movie(resumeAt: 2530))
        XCTAssertEqual(actions.map(\.title), ["Resume from 42:10", "Play from beginning"])
        XCTAssertEqual(actions.map(\.resume), [true, false])
    }

    func testPlaybackActionsForUnwatchedItem() {
        XCTAssertEqual(PlaybackActions.actions(for: movie()).map(\.title), ["Play"])
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
        let grid = LibraryGridModel { start, limit in
            ItemsResult(items: Array(all[start..<min(all.count, start + limit)]), totalRecordCount: all.count, startIndex: start)
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
