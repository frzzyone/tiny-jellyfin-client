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

/// A library's poster grid with paging.
@MainActor
@Observable
final class LibraryGridModel {
    static let pageSize = 60
    private(set) var items: [BaseItem] = []
    private(set) var total: Int?
    private(set) var error: String?
    private(set) var isLoading = false
    @ObservationIgnored private let fetchPage: (Int, Int) async throws -> ItemsResult

    init(fetchPage: @escaping (_ start: Int, _ limit: Int) async throws -> ItemsResult) {
        self.fetchPage = fetchPage
    }

    var hasMore: Bool { total.map { items.count < $0 } ?? true }

    func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await fetchPage(items.count, Self.pageSize)
            items += page.items
            total = page.totalRecordCount ?? items.count
            error = nil
        } catch is CancellationError {
        } catch {
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
