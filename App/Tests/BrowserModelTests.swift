import JellyfinKit
import XCTest
@testable import TinyJellyfin

@MainActor
final class BrowserModelTests: XCTestCase {
    let rows = [RowLayout(id: "hero", count: 1), RowLayout(id: "continue", count: 4), RowLayout(id: "nextUp", count: 2),
                RowLayout(id: "empty", count: 0), RowLayout(id: "latest", count: 7)]

    func testArrowsMoveBetweenRowsAndTitles() {
        var s = SelectionMath.move(nil, .down, rows: rows)
        XCTAssertEqual(s, BrowserSelection(row: "hero", index: 0))
        s = SelectionMath.move(s, .down, rows: rows)
        s = SelectionMath.move(s, .right, rows: rows)
        s = SelectionMath.move(s, .right, rows: rows)
        XCTAssertEqual(s, BrowserSelection(row: "continue", index: 2), "↓ ↓ → →")
        s = SelectionMath.move(s, .down, rows: rows)
        XCTAssertEqual(s, BrowserSelection(row: "nextUp", index: 1), "clamped to a shorter row")
        s = SelectionMath.move(s, .down, rows: rows)
        XCTAssertEqual(s?.row, "latest", "empty rows are skipped")
        s = SelectionMath.move(s, .left, rows: rows)
        XCTAssertEqual(s, BrowserSelection(row: "latest", index: 0))
        s = SelectionMath.move(s, .left, rows: rows)
        XCTAssertEqual(s?.index, 0, "stays at the start")
        XCTAssertNil(SelectionMath.move(BrowserSelection(row: "hero", index: 0), .up, rows: rows), "↑ from the top clears")
        XCTAssertNil(SelectionMath.move(nil, .up, rows: rows))
        XCTAssertNil(SelectionMath.move(nil, .down, rows: []))
        XCTAssertEqual(SelectionMath.move(BrowserSelection(row: "gone", index: 3), .down, rows: rows)?.row, "hero",
                       "a vanished row restarts at the top")
    }

    func testGridMovesByColumn() {
        let grid = [RowLayout(id: "filters", count: 4), RowLayout(id: "grid", count: 10, columns: 4)]
        var s = BrowserSelection(row: "grid", index: 1)
        s = SelectionMath.move(s, .down, rows: grid)!
        XCTAssertEqual(s.index, 5)
        s = SelectionMath.move(s, .down, rows: grid)!
        XCTAssertEqual(s.index, 9)
        XCTAssertEqual(SelectionMath.move(s, .down, rows: grid), s, "last row of the last grid stays")
        s = SelectionMath.move(s, .up, rows: grid)!
        XCTAssertEqual(s.index, 5)
        s = SelectionMath.move(BrowserSelection(row: "grid", index: 2), .up, rows: grid)!
        XCTAssertEqual(s, BrowserSelection(row: "filters", index: 2), "top row of the grid goes to the strip above")
        s = SelectionMath.move(BrowserSelection(row: "filters", index: 3), .down, rows: grid)!
        XCTAssertEqual(s, BrowserSelection(row: "grid", index: 3))
        s = SelectionMath.move(BrowserSelection(row: "grid", index: 9), .right, rows: grid)!
        XCTAssertEqual(s.index, 9)
        let below = grid + [RowLayout(id: "more", count: 3)]
        s = SelectionMath.move(BrowserSelection(row: "more", index: 2), .up, rows: below)!
        XCTAssertEqual(s, BrowserSelection(row: "grid", index: 9), "lands on the grid's last row, clamped")
    }

    func testTabsAreTheFirstKeyboardRowAndSwitchAtOnce() {
        let model = BrowserModel()
        model.tabs = [.home, .library("movies"), .library("shows")]
        model.setRows([(RowLayout(id: "hero", count: 1), [item("troy")]), (RowLayout(id: "nextUp", count: 3), [item("a"), item("b"), item("c")])], owner: "home")
        model.move(.down)
        XCTAssertEqual(model.selection, BrowserSelection(row: "hero", index: 0))
        model.move(.up)
        XCTAssertEqual(model.selection, BrowserSelection(row: "tabs", index: 0))
        XCTAssertEqual(model.tab, .home)
        model.move(.right)
        XCTAssertEqual(model.tab, .library("movies"), "moving along the tabs switches the tab")
        model.move(.right)
        model.move(.right)
        XCTAssertEqual(model.tab, .library("shows"), "stays at the last tab")
        model.setRows([(RowLayout(id: "grid", count: 10, columns: 5), (0..<10).map { item("g\($0)") })], owner: "movies")
        XCTAssertEqual(model.selection, BrowserSelection(row: "tabs", index: 2), "a new page keeps the tab selection")
        model.move(.down)
        XCTAssertEqual(model.selection, BrowserSelection(row: "grid", index: 2))
        XCTAssertEqual(model.selectedItem?.item.id, "g2")
        model.selectTab(number: 1)
        XCTAssertEqual(model.tab, .home)
        XCTAssertEqual(model.selection, BrowserSelection(row: "tabs", index: 0))
        model.selectTab(number: 7)
        XCTAssertEqual(model.tab, .home, "no such tab")
        XCTAssertNil(BrowserModel().selectedItem)
    }

    /// Movies → Home: SwiftUI shows Home (which publishes its rows) before Movies' onDisappear.
    /// Clearing then left Home without rows: ↓ stayed on the tabs, and an outlined title vanished.
    func testLeavingPageDoesNotClearTheNextPagesRows() {
        let model = BrowserModel()
        model.tabs = [.home, .library("movies")]
        model.setRows([(RowLayout(id: "grid", count: 4, columns: 4), (0..<4).map { item("g\($0)") })], owner: "movies")
        model.selection = BrowserSelection(row: "tabs", index: 1)
        model.move(.left)
        model.setRows([(RowLayout(id: "hero", count: 1), [item("troy")])], owner: "home")
        model.clearRows(owner: "movies")
        model.move(.down)
        XCTAssertEqual(model.selection, .hero, "↓ from the tabs reaches Home")
        model.clearRows(owner: "movies")
        XCTAssertEqual(model.selection, .hero, "a late clear keeps the outline")
        model.clearRows(owner: "home")
        XCTAssertNil(model.selection, "the page's own clear still works")
    }

    func testQuickLookStepsAlongItsRow() {
        let model = BrowserModel()
        let row = [item("a"), item("b"), item("c")]
        model.openQuickLook(row[1], in: row)
        XCTAssertTrue(model.stepQuickLook(forward: true))
        XCTAssertEqual(model.quickLook?.id, "c")
        XCTAssertFalse(model.stepQuickLook(forward: true), "end of the row")
        XCTAssertTrue(model.stepQuickLook(forward: false))
        XCTAssertTrue(model.stepQuickLook(forward: false))
        XCTAssertEqual(model.quickLook?.id, "a")
        var watched = item("a")
        watched.userData = UserItemData(played: true)
        model.update(watched)
        XCTAssertEqual(model.quickLook?.userData?.played, true)
        model.closeQuickLook()
        XCTAssertNil(model.quickLook)
        XCTAssertFalse(model.stepQuickLook(forward: true))
    }

    func testGridFiltersRestartPagingAndDropStaleResponses() async {
        let service = FakeLibraryService()
        let all = (0..<130).map { item("i\($0)") }
        service.onItems = { query in
            if query.searchTerm == "zz" { return [] }
            if query.filters == [.unplayed] && query.sort == .dateCreated { return Array(all.prefix(5)) }
            return all
        }
        let grid = LibraryGridModel(parentId: "lib") { try await service.items($0) }
        await grid.loadMore()
        XCTAssertEqual(grid.items.count, 60)
        XCTAssertEqual(grid.query.filters, [.unplayed])
        await grid.apply(filter: .longestUnseen)
        XCTAssertEqual(grid.items.count, 5)
        XCTAssertEqual(grid.query.sort, .dateCreated)
        XCTAssertFalse(grid.hasMore)
        await grid.apply(searchTerm: " zz ")
        XCTAssertEqual(grid.items.count, 0)
        XCTAssertEqual(grid.searchTerm, "zz")
        await grid.apply(searchTerm: "zz")
        XCTAssertEqual(service.queries.filter { $0.searchTerm == "zz" }.count, 1, "same term again is a no-op")
        await grid.apply(genreId: "g1")
        XCTAssertEqual(service.queries.last?.genreIds, ["g1"])
        let query = LibraryGridModel.query(parentId: nil, filter: .recent, genreId: nil, searchTerm: "he", startIndex: 60)
        XCTAssertEqual(query.sort, .dateCreated)
        XCTAssertTrue(query.descending)
        XCTAssertEqual(query.startIndex, 60)
        XCTAssertNil(query.parentId)
    }
}
