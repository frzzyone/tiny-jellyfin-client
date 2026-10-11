import Foundation

/// Secure storage for access tokens. The app uses the macOS Keychain; tests use `InMemoryTokenStore`.
/// Only tokens are stored — never passwords.
public protocol TokenStore: AnyObject, Sendable {
    func token(account: String) throws -> String?
    func setToken(_ token: String, account: String) throws
    func deleteToken(account: String) throws
}

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private var tokens: [String: String] = [:]
    private let lock = NSLock()
    public init() {}

    public func token(account: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return tokens[account]
    }

    public func setToken(_ token: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        tokens[account] = token
    }

    public func deleteToken(account: String) throws {
        lock.lock(); defer { lock.unlock() }
        tokens[account] = nil
    }

    public var allTokens: [String: String] {
        lock.lock(); defer { lock.unlock() }
        return tokens
    }
}

/// Non-secret preferences: server address, user, device id, preferred quality per server.
public final class AppPreferences: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let serverURL = "serverURL"
        static let userId = "userId"
        static let userName = "userName"
        static let deviceId = "deviceId"
        static let qualityPrefix = "preferredQuality."
    }

    public var serverURL: URL? {
        get { defaults.string(forKey: Key.serverURL).flatMap(URL.init(string:)) }
        set { defaults.set(newValue?.absoluteString, forKey: Key.serverURL) }
    }

    public var userId: String? {
        get { defaults.string(forKey: Key.userId) }
        set { defaults.set(newValue, forKey: Key.userId) }
    }

    public var userName: String? {
        get { defaults.string(forKey: Key.userName) }
        set { defaults.set(newValue, forKey: Key.userName) }
    }

    /// Generated once, then stable across launches so the server lists one device for this Mac.
    public var deviceId: String {
        if let existing = defaults.string(forKey: Key.deviceId) { return existing }
        let id = UUID().uuidString
        defaults.set(id, forKey: Key.deviceId)
        return id
    }

    public func preferredQualityId(server: URL) -> String? {
        defaults.string(forKey: Key.qualityPrefix + server.absoluteString)
    }

    public func setPreferredQualityId(_ id: String, server: URL) {
        defaults.set(id, forKey: Key.qualityPrefix + server.absoluteString)
    }

    public func clearUser() {
        defaults.removeObject(forKey: Key.userId)
        defaults.removeObject(forKey: Key.userName)
    }
}
