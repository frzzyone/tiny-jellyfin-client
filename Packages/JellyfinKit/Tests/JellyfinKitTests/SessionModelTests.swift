import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JellyfinKit

@MainActor
final class SessionModelTests: XCTestCase {
    var server: StubServer!
    var tokens: InMemoryTokenStore!
    var defaults: UserDefaults!
    var prefs: AppPreferences!

    override func setUp() async throws {
        server = StubServer()
        tokens = InMemoryTokenStore()
        let suite = "test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        prefs = AppPreferences(defaults: defaults)
        server.on("GET", "/System/Info/Public", json: #"{"ServerName":"Home","Version":"10.10.3","Id":"abc"}"#)
        server.on("POST", "/Users/AuthenticateByName",
                  json: #"{"User":{"Id":"u42","Name":"frank"},"AccessToken":"secret-token"}"#)
    }

    func makeModel() -> SessionModel {
        SessionModel(tokens: tokens, preferences: prefs, deviceName: "Test Mac", appVersion: "0.1.0",
                     urlSession: server.session)
    }

    func signedInModel() async -> SessionModel {
        let model = makeModel()
        await model.connect(address: server.baseURL.absoluteString)
        await model.signIn(username: "frank", password: "hunter2")
        return model
    }

    func testConnectToValidServer() async {
        let model = makeModel()
        await model.connect(address: server.host)  // no scheme → https
        guard case .signIn(let connected, _, nil) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(connected.name, "Home")
        XCTAssertEqual(connected.url.absoluteString, "https://\(server.host)")
    }

    func testConnectKeepsPlainHTTP() async {
        let httpServer = StubServer(scheme: "http")
        httpServer.on("GET", "/System/Info/Public", json: #"{"ServerName":"LAN","Version":"10.9.0","Id":"x"}"#)
        let model = SessionModel(tokens: tokens, preferences: prefs, deviceName: "Mac", appVersion: "1",
                                 urlSession: httpServer.session)
        await model.connect(address: httpServer.baseURL.absoluteString)
        guard case .signIn(let connected, _, _) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(connected.url.scheme, "http")
    }

    /// A home server on plain HTTP, typed without a scheme: https fails, http answers.
    func testAddressWithoutSchemeFallsBackToHTTP() async {
        let server = StubServer()
        server.on("GET", "/System/Info/Public") { request in
            guard request.url?.scheme == "http" else { throw URLError(.cannotConnectToHost) }
            return (200, Data(#"{"ServerName":"LAN","Version":"10.9.0","Id":"x"}"#.utf8))
        }
        let model = SessionModel(tokens: tokens, preferences: prefs, deviceName: "Mac", appVersion: "1", urlSession: server.session)
        await model.connect(address: server.host + ":8096")
        guard case .signIn(let connected, _, _) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(connected.url.absoluteString, "http://\(server.host):8096")
        XCTAssertEqual(server.requests.map { $0.url?.scheme }, ["https", "http"])
    }

    func testExplicitHTTPSIsNotDowngraded() async {
        let server = StubServer()
        server.on("GET", "/System/Info/Public") { _ in throw URLError(.serverCertificateUntrusted) }
        let model = SessionModel(tokens: tokens, preferences: prefs, deviceName: "Mac", appVersion: "1", urlSession: server.session)
        await model.connect(address: "https://" + server.host)
        guard case .serverEntry(_, let error) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(error, JellyfinError.untrustedCertificate.errorDescription, "a self-signed server is not 'not Jellyfin'")
        XCTAssertEqual(server.requests.count, 1, "no http retry when https was asked for")
    }

    func testUnreachableServerStaysOnServerStep() async {
        let model = makeModel()
        await model.connect(address: "https://nowhere.invalid-host.test")
        guard case .serverEntry(let prefill, let error) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(prefill, "https://nowhere.invalid-host.test")
        XCTAssertNotNil(error)
    }

    func testInvalidAddress() async {
        let model = makeModel()
        await model.connect(address: "not a url")
        guard case .serverEntry(_, let error) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertNotNil(error)
    }

    func testSignInStoresOnlyToken() async {
        let model = await signedInModel()
        guard case .signedIn(let session) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(session.userName, "frank")
        XCTAssertEqual(tokens.allTokens, ["https://\(server.host)|u42": "secret-token"])
        // The password never lands in preferences or the token store.
        let everything = defaults.dictionaryRepresentation().values.map { "\($0)" }.joined()
            + tokens.allTokens.values.joined()
        XCTAssertFalse(everything.contains("hunter2"))
        XCTAssertNotNil(model.client)
    }

    func testWrongPassword() async {
        server.on("POST", "/Users/AuthenticateByName", status: 401, json: "")
        let model = makeModel()
        await model.connect(address: server.baseURL.absoluteString)
        await model.signIn(username: "frank", password: "nope")
        guard case .signIn(_, let username, let error) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(username, "frank")
        XCTAssertEqual(error, "Incorrect username or password.")
        XCTAssertTrue(tokens.allTokens.isEmpty)
    }

    func testRestoreAfterRelaunch() async {
        _ = await signedInModel()
        let relaunched = makeModel()
        relaunched.restore()
        guard case .signedIn(let session) = relaunched.state else { return XCTFail("\(relaunched.state)") }
        XCTAssertEqual(session.userId, "u42")
        XCTAssertEqual(session.server.name, "Home", "the server's name, not its address")
        XCTAssertEqual(relaunched.client?.accessToken, "secret-token")
    }

    func testRestoreLearnsANameItNeverSaved() async throws {
        _ = await signedInModel()
        defaults.removeObject(forKey: "serverName")
        let relaunched = makeModel()
        relaunched.restore()
        for _ in 0..<50 {
            if case .signedIn(let session) = relaunched.state, session.server.name == "Home" { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("\(relaunched.state)")
    }

    func testRevokedTokenReturnsToSignIn() async throws {
        let model = await signedInModel()
        server.on("GET", "/Items/x", status: 401, json: "")
        _ = try? await model.client?.item(id: "x")
        // onUnauthorized hops to the main actor.
        for _ in 0..<50 where { if case .signedIn = model.state { return true }; return false }() {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard case .signIn(let connected, _, let error) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(connected.url.absoluteString, "https://\(server.host)")
        XCTAssertNotNil(error)
        XCTAssertTrue(tokens.allTokens.isEmpty)
    }

    func testSignOut() async {
        server.on("POST", "/Sessions/Logout", status: 204, json: "")
        let model = await signedInModel()
        await model.signOut()
        guard case .serverEntry = model.state else { return XCTFail("\(model.state)") }
        XCTAssertTrue(tokens.allTokens.isEmpty)
        XCTAssertNotNil(server.lastRequest(path: "/Sessions/Logout"))
        XCTAssertNil(prefs.userId)
    }

    func testSignOutWhileOfflineStillClearsToken() async {
        let model = await signedInModel()
        server.on("POST", "/Sessions/Logout") { _ in throw URLError(.notConnectedToInternet) }
        await model.signOut()
        guard case .serverEntry = model.state else { return XCTFail("\(model.state)") }
        XCTAssertTrue(tokens.allTokens.isEmpty)
    }

    func testDeviceIdIsStable() async {
        let first = prefs.deviceId
        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.deviceId, first)
        _ = await signedInModel()
        let header = server.lastRequest(path: "/Users/AuthenticateByName")?.value(forHTTPHeaderField: "Authorization")
        XCTAssertTrue(header?.contains("DeviceId=\"\(first)\"") == true)
    }
}

// MARK: Quick Connect

extension SessionModelTests {
    func connectedModel() async -> SessionModel {
        let model = makeModel()
        await model.connect(address: server.baseURL.absoluteString)
        return model
    }

    /// Answers `/QuickConnect/Connect` from a list: pending, pending, …, approved.
    func approve(after polls: Int, code: String = "482917") {
        server.on("GET", "/QuickConnect/Enabled", json: "true")
        server.on("POST", "/QuickConnect/Initiate", json: #"{"Authenticated":false,"Secret":"s1","Code":"\#(code)"}"#)
        let lock = NSLock()
        var count = 0
        server.on("GET", "/QuickConnect/Connect") { _ in
            lock.lock(); defer { lock.unlock() }
            count += 1
            return (200, Data(#"{"Authenticated":\#(count > polls),"Secret":"s1","Code":"\#(code)"}"#.utf8))
        }
        server.on("POST", "/Users/AuthenticateWithQuickConnect",
                  json: #"{"User":{"Id":"u42","Name":"frank"},"AccessToken":"qc-token"}"#)
    }

    func testQuickConnectApproved() async {
        approve(after: 2)
        let model = await connectedModel()
        await model.runQuickConnect(pollInterval: .milliseconds(5))
        guard case .signedIn(let session) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(session.userName, "frank")
        XCTAssertEqual(tokens.allTokens, ["https://\(server.host)|u42": "qc-token"])
        XCTAssertEqual(model.quickConnect, .idle)
        XCTAssertEqual(jsonBody(server.lastRequest(path: "/Users/AuthenticateWithQuickConnect"))["Secret"] as? String, "s1")
        XCTAssertEqual(queryValue(server.lastRequest(path: "/QuickConnect/Connect"), "secret"), "s1")
    }

    func testQuickConnectShowsCodeUntilCancelled() async throws {
        approve(after: .max)
        let model = await connectedModel()
        let task = Task { await model.runQuickConnect(pollInterval: .milliseconds(5)) }
        for _ in 0..<100 where model.quickConnect == .idle { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(model.quickConnect, .waiting(code: "482917"))
        task.cancel()
        await task.value
        XCTAssertEqual(model.quickConnect, .idle)
        guard case .signIn = model.state else { return XCTFail("\(model.state)") }
        XCTAssertTrue(tokens.allTokens.isEmpty)
    }

    func testQuickConnectDisabled() async {
        server.on("GET", "/QuickConnect/Enabled", json: "false")
        let model = await connectedModel()
        await model.runQuickConnect(pollInterval: .milliseconds(5))
        XCTAssertEqual(model.quickConnect, .unavailable)
        guard case .signIn = model.state else { return XCTFail("\(model.state)") }
    }

    func testQuickConnectExpiredCodeIsReplaced() async {
        approve(after: 0)
        let lock = NSLock()
        var initiated = 0
        server.on("POST", "/QuickConnect/Initiate") { _ in
            lock.lock(); defer { lock.unlock() }
            initiated += 1
            return (200, Data(#"{"Authenticated":false,"Secret":"s\#(initiated)","Code":"00000\#(initiated)"}"#.utf8))
        }
        let connect: StubURLProtocol.Handler = { request in
            let secret = queryValue(request, "secret")
            // The first code expired before anyone approved it; the second is approved at once.
            return secret == "s1" ? (404, Data()) : (200, Data(#"{"Authenticated":true,"Secret":"s2","Code":"000002"}"#.utf8))
        }
        server.on("GET", "/QuickConnect/Connect", handler: connect)
        let model = await connectedModel()
        await model.runQuickConnect(pollInterval: .milliseconds(5))
        guard case .signedIn = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(initiated, 2)
        XCTAssertEqual(jsonBody(server.lastRequest(path: "/Users/AuthenticateWithQuickConnect"))["Secret"] as? String, "s2")
    }
}
