import Foundation
import JellyfinKit

/// What the app downloads and deletes on its own: Smart Downloads and Downloads for you. Pure, so
/// the tests cover every rule; the downloader carries the plans out.
enum DownloadPlanner {
    /// Downloads for you never hold more than this, nor leave the phone with less free.
    static let budget: Int64 = 15_000_000_000
    static let freeFloor: Int64 = 5_000_000_000
    /// Next up shows kept ready, plus the top film of Continue watching.
    static let shows = 3

    /// Smart Downloads: a finished episode makes way for the next unwatched one of its series, which
    /// is the user's own download if the finished one was. A film stays.
    static func afterFinishing(_ record: DownloadRecord, next: BaseItem?, records: [DownloadRecord])
        -> (delete: String?, download: (item: BaseItem, kind: DownloadRecord.Kind)?) {
        guard record.item.type == .episode else { return (nil, nil) }
        let onPhone = Set(records.map(\.id))
        guard let next, next.id != record.id, !onPhone.contains(next.id) else { return (record.id, nil) }
        return (record.id, (next, record.kind))
    }

    struct Plan: Equatable {
        var download: [BaseItem] = []
        var delete: [String] = []
    }

    /// Downloads for you. Wanted: the first episode of each of the first `shows` series in Next up,
    /// then the first film in Continue watching. Missing ones are downloaded in that order while
    /// they fit the budget and the free-space floor; the first that doesn't fit stops the list, so
    /// nothing jumps ahead of it. Picks no longer wanted are deleted, except `busy` ones (playing,
    /// or with progress not yet sent). The user's own downloads count as ready and are never touched.
    static func forYou(nextUp: [BaseItem], resume: [BaseItem], records: [DownloadRecord], dismissed: Set<String>,
                       busy: Set<String>, freeBytes: Int64, size: (BaseItem) -> Int64) -> Plan {
        let wanted = wanted(nextUp: nextUp, resume: resume)
        let wantedIds = Set(wanted.map(\.id))
        let onPhone = Set(records.map(\.id))
        var used = records.filter { $0.kind == .forYou && wantedIds.contains($0.id) }.reduce(Int64(0)) { $0 + bytes($1) }
        // Space the downloads under way will still take.
        var free = freeBytes - records.filter { !$0.isDone }.reduce(Int64(0)) { $0 + max(0, $1.expectedBytes - $1.receivedBytes) }
        var plan = Plan()
        for item in wanted where !onPhone.contains(item.id) && !dismissed.contains(item.id) {
            let bytes = size(item)
            guard used + bytes <= budget, free - bytes >= freeFloor else { break }
            plan.download.append(item)
            used += bytes
            free -= bytes
        }
        plan.delete = records.filter { $0.kind == .forYou && !wantedIds.contains($0.id) && !busy.contains($0.id) }.map(\.id)
        return plan
    }

    /// Dismissed picks are remembered while they are still candidates; once one leaves the rows
    /// (watched, or the show moved on) it may be picked again, as a later episode would be.
    static func stillDismissed(_ dismissed: Set<String>, nextUp: [BaseItem], resume: [BaseItem]) -> Set<String> {
        dismissed.intersection(nextUp.map(\.id) + resume.map(\.id))
    }

    static func wanted(nextUp: [BaseItem], resume: [BaseItem]) -> [BaseItem] {
        var series = Set<String>()
        var wanted: [BaseItem] = []
        for episode in nextUp where series.count < shows {
            if series.insert(episode.seriesId ?? episode.id).inserted { wanted.append(episode) }
        }
        if let film = resume.first(where: { $0.type == .movie }) { wanted.append(film) }
        return wanted
    }

    /// What a download counts against the budget: its real size once done, the estimate before.
    static func bytes(_ record: DownloadRecord) -> Int64 {
        record.isDone ? record.receivedBytes : max(record.expectedBytes, record.receivedBytes)
    }
}
