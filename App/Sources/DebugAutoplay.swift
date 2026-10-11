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
        } catch {
            PlayerLog.engine("Autoplay failed: \(error)")
        }
    }
}
#endif
