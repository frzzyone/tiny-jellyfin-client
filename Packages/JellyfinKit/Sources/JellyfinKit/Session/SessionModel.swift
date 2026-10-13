import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ConnectedServer: Equatable, Sendable {
    public var url: URL
    public var name: String
}

public struct SignedInSession: Equatable, Sendable {
    public var server: ConnectedServer
    public var userId: String
    public var userName: String
}

public enum SessionState: Equatable, Sendable {
    /// Ask for a server address. `prefill` keeps what was typed before.
    case serverEntry(prefill: String, error: String?)
    /// Ask for username and password on a validated server.
    case signIn(server: ConnectedServer, username: String, error: String?)
    case signedIn(SignedInSession)
}

public enum QuickConnectState: Equatable, Sendable {
    case idle
    /// Show this code; someone signed in to Jellyfin elsewhere approves it.
    case waiting(code: String)
    /// Off on the server, or it failed: sign in with a password.
    case unavailable
}

/// Drives the connect → sign in → signed in flow, restores sessions on launch,
/// and returns to sign-in whenever the server rejects the token.
@MainActor
@Observable
public final class SessionModel {
    public private(set) var state: SessionState = .serverEntry(prefill: "", error: nil)
    public private(set) var isBusy = false
    public private(set) var client: JellyfinClient?
    public private(set) var quickConnect: QuickConnectState = .idle

    @ObservationIgnored private let tokens: TokenStore
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let urlSession: URLSession
    @ObservationIgnored private let deviceName: String
    @ObservationIgnored private let appVersion: String

    public init(tokens: TokenStore, preferences: AppPreferences, deviceName: String, appVersion: String,
                urlSession: URLSession = .shared) {
        self.tokens = tokens
        self.preferences = preferences
        self.deviceName = deviceName
        self.appVersion = appVersion
        self.urlSession = urlSession
    }

    public var identity: ClientIdentity {
        ClientIdentity(device: deviceName, deviceId: preferences.deviceId, version: appVersion)
    }

    /// The Keychain account a token is stored under.
    nonisolated public static func account(server: URL, userId: String) -> String { "\(server.absoluteString)|\(userId)" }

    private func makeClient(_ url: URL, token: String? = nil, userId: String? = nil) -> JellyfinClient {
        let client = JellyfinClient(baseURL: url, identity: identity, accessToken: token, userId: userId,
                                    session: urlSession)
        client.onUnauthorized = { [weak self] in
            Task { @MainActor in self?.handleUnauthorized() }
        }
        return client
    }

    /// Restores a stored session without contacting the server; a revoked token is
    /// detected on the first request (401 → `handleUnauthorized`).
    public func restore() {
        guard let url = preferences.serverURL else { return }
        guard let userId = preferences.userId,
              let token = try? tokens.token(account: Self.account(server: url, userId: userId)) else {
            state = .serverEntry(prefill: url.absoluteString, error: nil)
            return
        }
        client = makeClient(url, token: token, userId: userId)
        let server = ConnectedServer(url: url, name: url.host ?? url.absoluteString)
        state = .signedIn(SignedInSession(server: server, userId: userId, userName: preferences.userName ?? ""))
    }

    /// Validates the address and moves to sign-in.
    public func connect(address: String) async {
        isBusy = true
        defer { isBusy = false }
        let url: URL
        do {
            url = try ServerAddress.normalize(address)
        } catch {
            state = .serverEntry(prefill: address, error: (error as? JellyfinError)?.errorDescription)
            return
        }
        do {
            let info = try await makeClient(url).publicSystemInfo()
            let server = ConnectedServer(url: url, name: info.serverName ?? url.host ?? url.absoluteString)
            state = .signIn(server: server, username: "", error: nil)
        } catch {
            state = .serverEntry(prefill: address, error: JellyfinError.notJellyfin.errorDescription)
        }
    }

    public func signIn(username: String, password: String) async {
        guard case .signIn(let server, _, _) = state else { return }
        isBusy = true
        defer { isBusy = false }
        let client = makeClient(server.url)
        do {
            let result = try await client.authenticate(username: username, password: password)
            try finishSignIn(server: server, client: client, result: result)
        } catch JellyfinError.unauthorized {
            state = .signIn(server: server, username: username, error: JellyfinError.unauthorized.errorDescription)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = .signIn(server: server, username: username, error: message)
        }
    }

    /// Quick Connect on the sign-in step: shows a code and polls until someone approves it, then
    /// signs in. Runs until then; cancel the task to stop (leaving the screen). Expired codes are
    /// replaced with new ones.
    public func runQuickConnect(pollInterval: Duration = .seconds(3)) async {
        guard case .signIn(let server, _, _) = state else { return }
        let client = makeClient(server.url)
        func stillSigningIn() -> Bool {
            if case .signIn(let current, _, _) = state, current == server { return true }
            return false
        }
        do {
            guard try await client.quickConnectEnabled() else { quickConnect = .unavailable; return }
            while stillSigningIn() {
                let request = try await client.initiateQuickConnect()
                quickConnect = .waiting(code: request.code)
                var approved = false
                while !approved {
                    try await Task.sleep(for: pollInterval)
                    guard stillSigningIn() else { return }
                    do {
                        approved = try await client.quickConnectState(secret: request.secret).authenticated
                    } catch JellyfinError.server {
                        break  // expired
                    }
                }
                guard approved, stillSigningIn() else { continue }
                let result = try await client.authenticate(quickConnectSecret: request.secret)
                try finishSignIn(server: server, client: client, result: result)
            }
        } catch is CancellationError {
            quickConnect = .idle
        } catch {
            quickConnect = .unavailable
        }
    }

    private func finishSignIn(server: ConnectedServer, client: JellyfinClient, result: AuthenticationResult) throws {
        try tokens.setToken(result.accessToken, account: Self.account(server: server.url, userId: result.user.id))
        preferences.serverURL = server.url
        preferences.userId = result.user.id
        preferences.userName = result.user.name
        self.client = client
        quickConnect = .idle
        state = .signedIn(SignedInSession(server: server, userId: result.user.id, userName: result.user.name))
    }

    /// Back from sign-in to the server step.
    public func changeServer() {
        if case .signIn(let server, _, _) = state {
            state = .serverEntry(prefill: server.url.absoluteString, error: nil)
        }
    }

    /// Ends the session on the server when reachable; always removes the local token.
    public func signOut() async {
        guard case .signedIn(let session) = state else { return }
        let client = self.client
        self.client = nil
        removeStoredToken(session)
        state = .serverEntry(prefill: session.server.url.absoluteString, error: nil)
        client?.onUnauthorized = nil
        try? await client?.logout()
    }

    /// Token revoked or expired: forget it and ask for credentials on the same server.
    public func handleUnauthorized() {
        guard case .signedIn(let session) = state else { return }
        removeStoredToken(session)
        client = nil
        state = .signIn(server: session.server, username: session.userName,
                        error: "Your session has ended. Please sign in again.")
    }

    private func removeStoredToken(_ session: SignedInSession) {
        try? tokens.deleteToken(account: Self.account(server: session.server.url, userId: session.userId))
        preferences.clearUser()
    }
}
