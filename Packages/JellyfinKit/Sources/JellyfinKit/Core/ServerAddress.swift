import Foundation

public enum ServerAddress {
    /// Normalizes what the user typed into a server base URL:
    /// adds `https://` when no scheme is given, keeps an explicit `http://`,
    /// keeps port and path, and strips trailing slashes.
    public static func normalize(_ input: String) throws -> URL {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { throw JellyfinError.invalidAddress }
        let lower = text.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            if text.contains("://") { throw JellyfinError.invalidAddress }
            text = "https://" + text
        }
        guard var components = URLComponents(string: text),
              let host = components.host, !host.isEmpty else {
            throw JellyfinError.invalidAddress
        }
        components.scheme = components.scheme?.lowercased()
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        components.path = path
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw JellyfinError.invalidAddress }
        return url
    }
}
