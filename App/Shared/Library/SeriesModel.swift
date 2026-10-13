import Foundation
import JellyfinKit
import Observation

/// A series page: its seasons, the episodes of the one picked, and the episode Resume or Play
/// starts (the server's next up, else the first episode).
@MainActor
@Observable
final class SeriesModel {
    let series: BaseItem
    private(set) var seasons: [BaseItem] = []
    private(set) var season: BaseItem?
    private(set) var episodes: [BaseItem] = []
    private(set) var nextUp: BaseItem?
    private(set) var error: String?
    @ObservationIgnored private let service: LibraryService

    init(series: BaseItem, service: LibraryService) {
        self.series = series
        self.service = service
    }

    /// Opens on the season of the next episode.
    func load() async {
        do {
            async let next = service.nextUp(limit: 1, seriesId: series.id)
            seasons = try await service.seasons(seriesId: series.id)
            nextUp = try await next.first
            error = nil
            if let start = seasons.first(where: { $0.id == nextUp?.seasonId }) ?? seasons.first {
                await select(start)
            }
            if nextUp == nil { nextUp = episodes.first }
        } catch {
            self.error = describe(error)
        }
    }

    func select(_ season: BaseItem) async {
        self.season = season
        do {
            let list = try await service.episodes(seriesId: series.id, seasonId: season.id)
            // A slower answer for a season picked earlier must not replace this one's.
            guard self.season?.id == season.id else { return }
            episodes = list
            error = nil
        } catch {
            self.error = describe(error)
        }
    }

    /// An episode played or marked: refresh it, and what Resume points at.
    func refresh() async {
        if let season { await select(season) }
        nextUp = (try? await service.nextUp(limit: 1, seriesId: series.id))?.first ?? nextUp
    }
}
