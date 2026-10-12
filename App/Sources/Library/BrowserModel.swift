import Foundation
import JellyfinKit
import Observation

enum BrowserTab: Hashable {
    case home
    case library(String)
}

/// The outlined title: which row it is in and where.
struct BrowserSelection: Equatable {
    var row: String
    var index: Int

    static let hero = BrowserSelection(row: "hero", index: 0)
}

/// What the key handler needs to know about a row: how many titles, and whether it wraps into a
/// grid (`columns` > 0) or scrolls as one line (`columns` == 0).
struct RowLayout: Equatable {
    let id: String
    let count: Int
    var columns: Int = 0
}

enum MoveDirection { case up, down, left, right }

enum SelectionMath {
    /// Where the arrow keys take the selection. Rows are in visual order, top first.
    static func move(_ selection: BrowserSelection?, _ direction: MoveDirection, rows: [RowLayout]) -> BrowserSelection? {
        let rows = rows.filter { $0.count > 0 }
        guard !rows.isEmpty else { return nil }
        guard let selection, let current = rows.firstIndex(where: { $0.id == selection.id }) else {
            return direction == .down || direction == .right ? BrowserSelection(row: rows[0].id, index: 0) : nil
        }
        let row = rows[current]
        let index = min(selection.index, row.count - 1)
        switch direction {
        case .left:
            return BrowserSelection(row: row.id, index: max(0, index - 1))
        case .right:
            return BrowserSelection(row: row.id, index: min(row.count - 1, index + 1))
        case .down:
            if row.columns > 0, index + row.columns < row.count {
                return BrowserSelection(row: row.id, index: index + row.columns)
            }
            guard current + 1 < rows.count else { return BrowserSelection(row: row.id, index: index) }
            let next = rows[current + 1]
            let column = row.columns > 0 ? index % row.columns : index
            return BrowserSelection(row: next.id, index: min(column, next.count - 1))
        case .up:
            if row.columns > 0, index - row.columns >= 0 {
                return BrowserSelection(row: row.id, index: index - row.columns)
            }
            guard current > 0 else { return nil }
            let previous = rows[current - 1]
            let column = row.columns > 0 ? index % row.columns : index
            if previous.columns > 0 {
                // Land on the previous grid's last row, same column.
                let lastRowStart = ((previous.count - 1) / previous.columns) * previous.columns
                return BrowserSelection(row: previous.id, index: min(lastRowStart + column, previous.count - 1))
            }
            return BrowserSelection(row: previous.id, index: min(column, previous.count - 1))
        }
    }

    static func neighbour(of itemID: String, in items: [BaseItem], forward: Bool) -> BaseItem? {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return nil }
        let next = forward ? index + 1 : index - 1
        return items.indices.contains(next) ? items[next] : nil
    }
}

private extension BrowserSelection {
    var id: String { row }
}

/// Tabs, the keyboard selection, the quick look and the search text: the browser's shared state.
@MainActor
@Observable
final class BrowserModel {
    var tab: BrowserTab = .home
    var selection: BrowserSelection?
    var searchText = ""
    private(set) var quickLook: BaseItem?
    /// The row the quick look was opened from, for ← and →.
    @ObservationIgnored private var quickLookRow: [BaseItem] = []

    func openQuickLook(_ item: BaseItem, in row: [BaseItem]) {
        quickLook = item
        quickLookRow = row
    }

    func closeQuickLook() {
        quickLook = nil
        quickLookRow = []
    }

    /// Moves the quick look along its row; false when it is at the end.
    @discardableResult
    func stepQuickLook(forward: Bool) -> Bool {
        guard let current = quickLook,
              let next = SelectionMath.neighbour(of: current.id, in: quickLookRow, forward: forward) else { return false }
        quickLook = next
        return true
    }

    /// Keeps the quick look's item fresh after Mark watched.
    func update(_ item: BaseItem) {
        if quickLook?.id == item.id { quickLook = item }
        if let index = quickLookRow.firstIndex(where: { $0.id == item.id }) { quickLookRow[index] = item }
    }
}
