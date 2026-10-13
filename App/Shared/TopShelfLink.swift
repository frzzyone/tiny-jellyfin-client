import Foundation

/// Links the Apple TV's Top Shelf hands the app: `tinyjellyfin://item/<id>` opens the title's page,
/// `tinyjellyfin://play/<id>` resumes it.
struct TopShelfLink: Equatable {
    var itemId: String
    var play: Bool

    init(itemId: String, play: Bool) {
        self.itemId = itemId
        self.play = play
    }

    init?(url: URL) {
        guard url.scheme == "tinyjellyfin", let host = url.host, host == "item" || host == "play",
              let id = url.pathComponents.dropFirst().first, !id.isEmpty else { return nil }
        self.init(itemId: id, play: host == "play")
    }

    var url: URL { URL(string: "tinyjellyfin://\(play ? "play" : "item")/\(itemId)")! }
}
