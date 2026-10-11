import Foundation
#if canImport(os)
import os
#endif

/// Diagnostics that show up in Xcode's console and Console.app
/// (subsystem `app.tinyjellyfin`, categories `engine` and `network`).
public enum PlayerLog {
    #if canImport(os)
    static let engine = Logger(subsystem: "app.tinyjellyfin", category: "engine")
    static let network = Logger(subsystem: "app.tinyjellyfin", category: "network")
    #endif

    public static func engine(_ message: @autoclosure () -> String) {
        #if canImport(os)
        let text = message()
        engine.notice("\(text, privacy: .public)")
        #endif
    }

    public static func network(_ message: @autoclosure () -> String) {
        #if canImport(os)
        let text = message()
        network.notice("\(text, privacy: .public)")
        #endif
    }
}
