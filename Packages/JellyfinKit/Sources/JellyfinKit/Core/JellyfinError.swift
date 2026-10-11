import Foundation

public enum JellyfinError: Error, Equatable, Sendable {
    /// The server rejected the credentials or token (HTTP 401).
    case unauthorized
    /// The server answered with an unexpected status code.
    case server(status: Int, message: String?)
    /// The request never got a usable response (offline, DNS, TLS, timeout…).
    case network(String)
    /// The response body could not be decoded.
    case decoding(String)
    /// The address is not a usable server URL.
    case invalidAddress
    /// The server reachable at the address does not look like Jellyfin.
    case notJellyfin
    /// The server could not produce any stream this client can play.
    case noPlayableStream(String?)
}

extension JellyfinError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthorized: return "Incorrect username or password."
        case .server(let status, let message): return message ?? "The server returned an error (\(status))."
        case .network(let message): return "The server could not be reached. \(message)"
        case .decoding: return "The server sent a response this app does not understand."
        case .invalidAddress: return "That doesn't look like a server address."
        case .notJellyfin: return "The server could not be reached, or it is not a Jellyfin server."
        case .noPlayableStream(let reason):
            return "This video can't be played." + (reason.map { " (\($0))" } ?? "")
        }
    }
}
