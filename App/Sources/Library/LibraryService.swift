import Foundation
import JellyfinKit

/// What the browser needs from the server, so the models can be tested against a fake.
protocol LibraryService: AnyObject, Sendable {
    func libraries() async throws -> [BaseItem]
    func resumeItems() async throws -> [BaseItem]
    func nextUp(limit: Int, seriesId: String?) async throws -> [BaseItem]
    func latest(limit: Int) async throws -> [BaseItem]
    func items(_ query: ItemQuery) async throws -> ItemsResult
    func similar(to itemId: String, limit: Int) async throws -> [BaseItem]
    func genres(libraryId: String?) async throws -> [NameGuidPair]
    func seasons(seriesId: String) async throws -> [BaseItem]
    func episodes(seriesId: String, seasonId: String) async throws -> [BaseItem]
    func item(id: String) async throws -> BaseItem
    func markPlayed(_ itemId: String, played: Bool) async throws -> UserItemData
    func primaryImageURL(for item: BaseItem, maxHeight: Int) -> URL?
    func backdropImageURL(for item: BaseItem, maxWidth: Int) -> URL?
}

extension JellyfinClient: LibraryService {
    func resumeItems() async throws -> [BaseItem] { try await resumeItems(limit: 24) }
}

extension LibraryService {
    func nextUp(limit: Int = 24) async throws -> [BaseItem] { try await nextUp(limit: limit, seriesId: nil) }
    func posterURL(for item: BaseItem) -> URL? { primaryImageURL(for: item, maxHeight: 450) }
    func backdropURL(for item: BaseItem) -> URL? { backdropImageURL(for: item, maxWidth: 1600) }
}
