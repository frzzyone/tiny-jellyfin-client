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

    init() {
        let preferences = AppPreferences()
        self.preferences = preferences
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        session = SessionModel(tokens: KeychainTokenStore(), preferences: preferences,
                               deviceName: Self.deviceName, appVersion: version)
        player = PlaybackController(engineFactory: { FFmpegEngine() }, preferences: preferences,
                                    capabilities: PlaybackCapabilities(EngineCapabilities.current()))
        FFmpegLog.configure()
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
        guard let client else { return }
        player.start(item: item, resume: resume, service: JellyfinPlaybackService(client: client))
    }
}

extension PlaybackCapabilities {
    /// What we tell the server we can play, from what the engine reports for this Mac.
    init(_ engine: EngineCapabilities) {
        self.init(av1: engine.av1, hevc10Bit: engine.hevc, dolbyVision: engine.dolbyVision)
    }
}
