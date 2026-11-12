import Foundation
import JellyfinKit

/// What the server is told about viewing done on the phone.
protocol ProgressServer {
    func userData(itemId: String) async throws -> UserItemData?
    @discardableResult
    func updateUserData(_ itemId: String, positionSeconds: Double, played: Bool, lastPlayed: Date) async throws -> UserItemData
}

extension JellyfinClient: ProgressServer {
    func userData(itemId: String) async throws -> UserItemData? { try await item(id: itemId).userData }
}

/// Where the user stopped in each download, kept on the phone until the server has it. One file,
/// the latest record per item.
final class ProgressQueue {
    struct Entry: Codable, Equatable {
        var positionSeconds: Double
        var played: Bool
        var watched: Date
    }

    private let url: URL
    private(set) var entries: [String: Entry]

    init(url: URL) {
        self.url = url
        entries = (try? JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: url))) ?? [:]
    }

    /// Records a stop or a progress tick. 90% or more counts as watched, as on Jellyfin.
    func record(itemId: String, positionSeconds: Double, runtimeSeconds: Double?, ended: Bool = false, at date: Date = Date()) {
        let played = ended || (runtimeSeconds.map { $0 > 0 && positionSeconds >= $0 * 0.9 } ?? false)
        entries[itemId] = Entry(positionSeconds: played ? 0 : positionSeconds, played: played, watched: date)
        save()
    }

    /// Sends every entry. An entry the server watched past since (a later `lastPlayedDate`) is
    /// dropped; one that fails stays for next time. Returns whether each item it settled ended up
    /// watched on the server.
    @discardableResult
    func flush(to server: ProgressServer) async -> [String: Bool] {
        var settled: [String: Bool] = [:]
        for (itemId, entry) in entries {
            do {
                let current = try await server.userData(itemId: itemId)
                if let last = current?.lastPlayedDate.flatMap(Self.date), last > entry.watched {
                    settled[itemId] = current?.played ?? false
                } else {
                    try await server.updateUserData(itemId, positionSeconds: entry.positionSeconds, played: entry.played,
                                                    lastPlayed: entry.watched)
                    settled[itemId] = entry.played
                }
                // Only if nothing newer was recorded while the request ran.
                if entries[itemId] == entry { entries[itemId] = nil }
            } catch {
                continue
            }
        }
        save()
        return settled
    }

    private func save() {
        try? JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }

    /// Jellyfin writes up to seven fraction digits ("2026-11-10T08:30:00.0000000Z"), more than
    /// `ISO8601DateFormatter` reads.
    static func date(_ text: String) -> Date? {
        let plain = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: plain)
    }
}
