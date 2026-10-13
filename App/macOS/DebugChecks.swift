#if DEBUG
import AppKit
import JellyfinKit
import PlayerCore

/// Diagnostics hook: drives the open player with synthetic clicks, keys and trackpad swipes, sent
/// inside the app (the real pointer and keyboard are untouched), and writes PASS/FAIL lines to the
/// file named by `TJ_MAC_CHECKS`. Started by `DebugAutoplay` once playback runs. Debug builds only.
///
/// It brings the player to the front and goes full screen once. The last check plays to the end,
/// so pick an item that is already watched (`DebugAutoplay` does when no item is given).
/// Trackpad scrubbing isn't covered: a synthesized scroll event has no window, so the player
/// (rightly) ignores it; that one needs a hand on a trackpad.
@MainActor
struct DebugChecks {
    let player: PlaybackController
    let out: URL
    private var window: NSWindow? { NSApp.windows.first { $0.isVisible && $0.title == player.item?.displayName } }

    static func run(player: PlaybackController, out: String) async {
        let checks = DebugChecks(player: player, out: URL(fileURLWithPath: out))
        try? "".write(to: checks.out, atomically: true, encoding: .utf8)
        await checks.run()
    }

    private func report(_ line: String) {
        PlayerLog.engine("Check: \(line)")
        guard let handle = try? FileHandle(forWritingTo: out) else { return }
        handle.seekToEndOfFile()
        handle.write(Data((line + "\n").utf8))
        try? handle.close()
    }

    private func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        report("\(ok ? "PASS" : "FAIL") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    }

    private func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    private func waitUntil(_ timeout: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            await wait(0.1)
        }
        return true
    }

    private func run() async {
        guard await waitUntil(60, { player.status == .playing }) else { return report("FAIL never started playing") }
        await wait(1)
        guard let window else {
            return check("window title", false, "no window titled '\(player.item?.displayName ?? "")' among \(NSApp.windows.map(\.title))")
        }
        check("window title", true, "'\(window.title)'")
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        await wait(1)

        // Click to pause and play (a single click waits out the double-click interval).
        await click(window)
        await wait(0.8)
        check("click pauses", !player.isPlaying, "status \(player.status)")
        await click(window)
        await wait(0.8)
        check("click plays", player.isPlaying, "status \(player.status)")

        // Double-click: full screen, and it must not pause.
        await click(window, count: 2)
        let full = await waitUntil(4) { window.styleMask.contains(.fullScreen) }
        check("double-click full screen", full)
        check("double-click doesn't pause", player.isPlaying, "status \(player.status)")
        if full {
            window.toggleFullScreen(nil)
            _ = await waitUntil(4) { !window.styleMask.contains(.fullScreen) }
            await wait(1)
        }

        // S: each text subtitle, then off.
        let text = player.subtitleOptions.filter { !$0.isImage }.map(\.id)
        if text.isEmpty {
            report("SKIP S key — no text subtitles (\(player.subtitleOptions.count) image tracks)")
        } else {
            var seen: [Int?] = []
            for _ in 0...text.count {
                key(window, "s", code: 1)
                await wait(0.5)
                seen.append(player.selectedSubtitle)
            }
            check("S cycles text subtitles then off", seen == text.map(Optional.some) + [nil], "\(seen)")
        }

        // Digits: tenths of the film.
        for (digit, code) in [(5, UInt16(23)), (0, 29)] {
            key(window, Character(String(digit)), code: code)
            let target = player.duration * Double(digit) / 10
            let landed = await waitUntil(30) { abs(player.position - target) < 15 && player.status == .playing }
            check("key \(digit) jumps to \(Int(target)) s", landed, String(format: "at %.0f s", player.position))
        }

        // The end: "Watched" with Play Again and Close, and a click doesn't restart it.
        await player.seek(to: player.duration - 6)
        let ended = await waitUntil(60) { player.status == .ended }
        check("plays to the end", ended, "status \(player.status)")
        if ended {
            report("ENDED \(window.windowNumber) — capture now")
            await wait(6)
            await click(window, at: 0.2) // away from Play Again in the middle
            await wait(0.8)
            check("click at the end does nothing", player.status == .ended, "status \(player.status)")
        }
        report("DONE")
    }

    // MARK: Synthetic events, delivered through NSApp so local monitors and SwiftUI see them

    /// Press and release 80 ms apart, the clicks of a double-click 150 ms apart, as a hand would.
    private func click(_ window: NSWindow, count: Int = 1, at x: Double = 0.5) async {
        let rect = window.contentLayoutRect
        let point = NSPoint(x: rect.minX + rect.width * x, y: rect.midY)
        for n in 1...count {
            if n > 1 { await wait(0.15) }
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if type == .leftMouseUp { await wait(0.08) }
                if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: n, pressure: 1) {
                    NSApp.sendEvent(event)
                }
            }
        }
    }

    private func key(_ window: NSWindow, _ character: Character, code: UInt16) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil, characters: String(character),
                                            charactersIgnoringModifiers: String(character), isARepeat: false, keyCode: code) {
                NSApp.sendEvent(event)
            }
        }
    }
}
#endif
