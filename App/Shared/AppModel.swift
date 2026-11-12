import Foundation
#if canImport(UIKit)
import UIKit
#endif
import JellyfinKit
import Observation
import PlayerCore

/// App-wide state: the session, preferences, and the single playback controller.
@MainActor
@Observable
final class AppModel {
    static let playerWindowID = "player"

    let preferences: AppPreferences
    let session: SessionModel
    let player: PlaybackController
    #if os(iOS)
    let downloads = Downloads(store: DownloadStore(), server: { nil }, probe: MediaFileInfo.read)
    #endif

    init() {
        #if os(tvOS)
        // Shared with the Top Shelf extension.
        var preferences = AppPreferences(defaults: TVShared.defaults)
        #else
        var preferences = AppPreferences()
        #endif
        var tokens: TokenStore = KeychainTokenStore()
        #if os(macOS) && DEBUG
        // Screenshot hook: TJ_SERVER=<address> TJ_USER=<name> signs in with an empty password (the
        // demo server's account), kept in memory and in its own defaults, so the real sign-in and
        // settings are left alone.
        if ProcessInfo.processInfo.environment["TJ_SERVER"] != nil {
            let defaults = UserDefaults(suiteName: "app.tinyjellyfin.debug-session")!
            defaults.removePersistentDomain(forName: "app.tinyjellyfin.debug-session")
            preferences = AppPreferences(defaults: defaults)
            tokens = InMemoryTokenStore()
        }
        #endif
        self.preferences = preferences
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        session = SessionModel(tokens: tokens, preferences: preferences,
                               deviceName: Self.deviceName, appVersion: version)
        player = PlaybackController(engineFactory: { FFmpegEngine() }, preferences: preferences,
                                    capabilities: PlaybackCapabilities(EngineCapabilities.current()))
        FFmpegLog.configure()
        #if os(iOS)
        let capabilities = PlaybackCapabilities(EngineCapabilities.current())
        downloads.server = { [weak self] in
            self?.session.client.map { JellyfinDownloadServer(client: $0, capabilities: capabilities) }
        }
        #endif
    }

    var client: JellyfinClient? { session.client }

    /// What the server's device list shows for this machine.
    private static var deviceName: String {
        #if os(macOS)
        Host.current().localizedName ?? "Mac"
        #else
        UIDevice.current.name
        #endif
    }

    /// Starts playback of an item in the player window (one playback at a time).
    func play(_ item: BaseItem, resume: Bool) {
        #if os(iOS)
        // A downloaded title plays from the phone, connected or not.
        if let local = downloads.playbackService(for: item) {
            downloads.playingId = item.id
            player.start(item: item, resume: resume, service: local)
            return
        }
        #endif
        guard let client else { return }
        player.start(item: item, resume: resume, service: JellyfinPlaybackService(client: client))
    }

    /// Signs out; on the iPhone, downloads go too, after what was watched is sent.
    func signOut() async {
        #if os(iOS)
        await downloads.signOut()
        #endif
        await session.signOut()
    }
}

extension PlaybackCapabilities {
    /// What we tell the server we can play, from what the engine reports for this Mac.
    init(_ engine: EngineCapabilities) {
        self.init(av1: engine.av1, hevc10Bit: engine.hevc, dolbyVision: engine.dolbyVision)
    }
}
