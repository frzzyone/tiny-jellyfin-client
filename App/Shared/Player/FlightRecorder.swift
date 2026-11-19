#if !os(macOS)
import Darwin
import Foundation
import JellyfinKit
import MachO

/// What the player did in its last minutes, kept in a file so that a crash, or a kill for memory
/// (which leaves the developer no crash report at all), leaves it behind. Every 10 s during
/// playback: memory left before the system kills the app, the app's footprint, the engine's state.
/// A crash adds its signal or exception and the stack. The next launch sends a log that ended
/// mid-playback to the user's own Jellyfin server (Dashboard › Logs, `upload_…`).
@MainActor
enum FlightRecorder {
    static let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("flight-recorder.log")
    // ponytail: the last 90 records (15 minutes) rewritten each tick; a ring file if it ever runs all the time.
    private static var lines: [String] = []
    private static var timer: Timer?

    /// Sends the last session's log if it ended during playback, then starts a new one.
    static func start(player: PlaybackController, client: @escaping () -> JellyfinClient?) {
        let previous = try? String(contentsOf: url, encoding: .utf8)
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        // The image address lets a stack be symbolicated against the archive's dSYM.
        lines = ["launch \(Date()) build \(build) image \(String(format: "0x%lx", Int(bitPattern: _dyld_get_image_header(0))))"]
        save()
        installCrashHandlers()
        if let previous, endedDuringPlayback(previous) {
            Task {
                // The session restores asynchronously; wait for a signed-in client.
                for _ in 0..<20 where client() == nil { try? await Task.sleep(for: .milliseconds(500)) }
                _ = try? await client()?.uploadClientLog(previous)
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            MainActor.assumeIsolated { tick(player) }
        }
    }

    /// The last record was taken while something played, or is a crash: the app went mid-film.
    nonisolated static func endedDuringPlayback(_ log: String) -> Bool {
        let records = log.split(separator: "\n").filter { $0.hasPrefix("t ") || $0.hasPrefix("idle") || $0.hasPrefix("crash") }
        return records.last.map { !$0.hasPrefix("idle") } ?? false
    }

    private static func tick(_ player: PlaybackController) {
        guard let item = player.item else {
            if lines.last?.hasPrefix("t ") == true { lines.append("idle"); save() }
            return
        }
        lines.append("t \(Date().formatted(date: .omitted, time: .standard)) left=\(os_proc_available_memory() / 1_048_576)MB "
                     + "footprint=\(footprint())MB item=\(item.displayName) \(player.status) at=\(Int(player.currentTime)) "
                     + (player.engine?.debugSummary ?? ""))
        lines = Array(lines.suffix(90))
        save()
    }

    /// In place, not atomically: the crash handlers append through a descriptor opened on this file.
    private static func save() {
        try? lines.joined(separator: "\n").appending("\n").write(to: url, atomically: false, encoding: .utf8)
    }

    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint / 1_048_576 : 0
    }

    // MARK: Crashes

    nonisolated(unsafe) private static var crashFD: Int32 = -1

    private static func installCrashHandlers() {
        crashFD = open(url.path, O_WRONLY | O_APPEND)
        NSSetUncaughtExceptionHandler { exception in
            let text = "crash exception \(exception.name.rawValue): \(exception.reason ?? "")\n"
                + exception.callStackSymbols.joined(separator: "\n") + "\n"
            text.withCString { _ = Darwin.write(FlightRecorder.crashFD, $0, strlen($0)) }
        }
        // ponytail: allocates inside a signal handler, which is not async-signal-safe; good enough to
        // learn where a crash happened, since the process is going anyway.
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE] {
            signal(sig) { number in
                let fd = FlightRecorder.crashFD
                let header = Array("crash signal \(number)\n".utf8)
                _ = header.withUnsafeBufferPointer { Darwin.write(fd, $0.baseAddress, $0.count) }
                var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 64)
                backtrace_symbols_fd(&frames, backtrace(&frames, 64), fd)
                signal(number, SIG_DFL)
                raise(number)
            }
        }
    }
}
#endif
