#if DEBUG
import JellyfinKit
import PlayerCore
import SwiftUI

/// Diagnostics hook: start playback on launch so the open path can be measured against a real
/// server without clicking through the UI. Debug builds only.
///
///     TJ_AUTOPLAY=1                 play the first Continue Watching item
///     TJ_AUTOPLAY_ITEM=<item id>    play a specific item instead
///     TJ_AUTOPLAY_SEARCH=<title>    …or the first film or episode found by title
///     TJ_AUTOPLAY_FROM_START=1      ignore the saved resume position
///     TJ_AUTOPLAY_QUALITY=<id>      force a quality (e.g. original, 720p-4)
///     TJ_AUTOPLAY_FULLSCREEN=1      toggle full screen 3 s after playback starts, and log the result
///     TJ_AUTOPLAY_SWITCH=<id>       switch to this quality once playing
///     TJ_AUTOPLAY_SWITCH_AFTER=<s>  …after this many seconds of playback (default 8)
///     TJ_AUTOPLAY_AUDIO=<index>     switch to this audio track once playing (same delay)
///     TJ_AUTOPLAY_SUBTITLE=<index>  select this subtitle once playing; `picture` picks the first
///                                   picture track
///     TJ_MAC_CHECKS=<file>          run `DebugChecks` on the player, results to the file; without
///                                   TJ_AUTOPLAY_ITEM it plays a film that is already watched
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
            } else if let title = env["TJ_AUTOPLAY_SEARCH"] {
                var query = ItemQuery(types: [.movie, .episode], limit: 1)
                query.searchTerm = title
                item = try await client.items(query).items.first
            } else if env["TJ_MAC_CHECKS"] != nil {
                // The checks play to the end, which would mark an unwatched film watched.
                item = try await client.items(ItemQuery(types: [.movie], filters: [.played], sort: .random, limit: 1)).items.first
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
            if let out = env["TJ_MAC_CHECKS"] {
                await DebugChecks.run(player: model.player, out: out)
                return
            }
            if env["TJ_AUTOPLAY_FULLSCREEN"] != nil {
                _ = await waitUntil { model.player.status == .playing }
                try await Task.sleep(nanoseconds: 3_000_000_000)
                guard let window = NSApp.windows.first(where: { $0.title == "Player" }) else {
                    PlayerLog.engine("Autoplay: no window titled Player among \(NSApp.windows.map { "'\($0.title)' \(type(of: $0))" })")
                    return
                }
                func describe(_ tag: String) {
                    PlayerLog.engine("Autoplay fullscreen \(tag): fullScreen=\(window.styleMask.contains(.fullScreen))"
                                     + " behavior=\(window.collectionBehavior.rawValue) frame=\(window.frame)")
                }
                describe("before")
                window.toggleFullScreen(nil)
                try await Task.sleep(nanoseconds: 4_000_000_000)
                describe("after")
            }
            if let wanted = env["TJ_AUTOPLAY_SUBTITLE"] {
                _ = await waitUntil { model.player.status == .playing }
                let options = model.player.subtitleOptions
                PlayerLog.engine("Autoplay: subtitles \(options.map { "\($0.id)\($0.isImage ? " picture" : "") \($0.label)" })")
                if let index = Int(wanted) ?? (wanted == "picture" ? options.first(where: \.isImage)?.id : nil) {
                    PlayerLog.engine("Autoplay: selecting subtitle \(index)")
                    model.player.selectSubtitle(index)
                }
            }
            if let audio = env["TJ_AUTOPLAY_AUDIO"].flatMap(Int.init) {
                let delay = env["TJ_AUTOPLAY_SWITCH_AFTER"].flatMap(Double.init) ?? 8
                _ = await waitUntil { model.player.status == .playing }
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                PlayerLog.engine("Autoplay: switching to audio track \(audio)")
                model.player.selectAudio(audio)
            }
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
