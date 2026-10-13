import Foundation
import JellyfinKit
import TVServices
import UIKit

/// The Top Shelf above the app's icon: Continue watching and Next up, with progress. Selecting an
/// item opens its page in the app; Play starts it.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent() async -> TVTopShelfContent? {
        let preferences = AppPreferences(defaults: TVShared.defaults)
        guard let server = preferences.serverURL, let userId = preferences.userId,
              let token = try? KeychainTokenStore().token(account: SessionModel.account(server: server, userId: userId))
        else { return nil } // not signed in: the static Top Shelf image shows
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let identity = ClientIdentity(device: await UIDevice.current.name, deviceId: preferences.deviceId, version: version)
        let client = JellyfinClient(baseURL: server, identity: identity, accessToken: token, userId: userId)

        async let resume = try? client.resumeItems(limit: 10)
        async let next = try? client.nextUp(limit: 10)
        let sections = [("Continue watching", await resume ?? []), ("Next up", await next ?? [])]
            .filter { !$0.1.isEmpty }
            .map { title, items in
                let section = TVTopShelfItemCollection(items: items.map { Self.shelfItem($0, client: client) })
                section.title = title
                return section
            }
        return sections.isEmpty ? nil : TVTopShelfSectionedContent(sections: sections)
    }

    static func shelfItem(_ item: BaseItem, client: JellyfinClient) -> TVTopShelfSectionedItem {
        let shelf = TVTopShelfSectionedItem(identifier: item.id)
        shelf.imageShape = .hdtv
        if item.type == .episode {
            let label = item.episodeLabel?.replacingOccurrences(of: " · ", with: " ")
            shelf.title = [item.seriesName, label].compactMap { $0 }.joined(separator: " · ")
        } else {
            shelf.title = item.displayName
        }
        // An episode's own picture is a still from it; a film's is its poster, so use the backdrop.
        let image = item.type == .episode
            ? client.primaryImageURL(for: item, maxHeight: 720) ?? client.backdropImageURL(for: item, maxWidth: 1280)
            : client.backdropImageURL(for: item, maxWidth: 1280)
        shelf.setImageURL(image, for: [.screenScale1x, .screenScale2x])
        if let pct = item.userData?.playedPercentage, pct > 0, item.userData?.played != true {
            shelf.playbackProgress = pct / 100
        }
        shelf.displayAction = TVTopShelfAction(url: TopShelfLink(itemId: item.id, play: false).url)
        shelf.playAction = TVTopShelfAction(url: TopShelfLink(itemId: item.id, play: true).url)
        return shelf
    }
}
