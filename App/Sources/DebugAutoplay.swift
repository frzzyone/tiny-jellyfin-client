#if DEBUG
import JellyfinKit
import PlayerCore
import SwiftUI

/// Diagnostics hook: start playback on launch so the open path can be measured against a real
/// server without clicking through the UI. Debug builds only.
///
///     TJ_AUTOPLAY=1                 play the first Continue Watching item
///     TJ_AUTOPLAY_ITEM=<item id>    play a specific item instead
///     TJ_AUTOPLAY_FROM_START=1      ignore the saved resume position
///     TJ_AUTOPLAY_QUALITY=<id>      force a quality (e.g. original, 720p-4)
///     TJ_AUTOPLAY_SWITCH=<id>       switch to this quality once playing
///     TJ_AUTOPLAY_SWITCH_AFTER=<s>  …after this many seconds of playback (default 8)
enum DebugAutoplay {
    @MainActor
    static func runIfRequested(model: AppModel, openWindow: OpenWindowAction) async {
        let env = ProcessInfo.processInfo.environment
        guard env["TJ_AUTOPLAY"] != nil, let client = model.client else { return }
        if let quality = env["TJ_AUTOPLAY_QUALITY"], QualityPreset.with(id: quality) != nil {
            model.preferences.setPreferredQualityId(quality, server: client.baseURL)
        }
        do {
            let item: BaseItem?
            if let id = env["TJ_AUTOPLAY_ITEM"] {
                item = try await client.item(id: id)
            } else {
                item = try await client.resumeItems(limit: 1).first
            }
            guard let item else {
                PlayerLog.engine("Autoplay: nothing in Continue Watching")
                return
            }
            PlayerLog.engine("Autoplay: \(item.displayName) [\(item.id)]")
            model.play(item, resume: env["TJ_AUTOPLAY_FROM_START"] == nil)
            openWindow(id: AppModel.playerWindowID)
            if let target = env["TJ_AUTOPLAY_SWITCH"], let quality = QualityPreset.with(id: target) {
                let delay = env["TJ_AUTOPLAY_SWITCH_AFTER"].flatMap(Double.init) ?? 8
                _ = await waitUntil { model.player.status == .playing }
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                PlayerLog.engine("Autoplay: switching to \(quality.label) at \(String(format: "%.3f", model.player.position)) s")
                model.player.selectQuality(quality)
            }
        } catch {
            PlayerLog.engine("Autoplay failed: \(error)")
        }
    }

    @MainActor
    private static func waitUntil(timeout: TimeInterval = 60, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return true
    }
}
#endif
