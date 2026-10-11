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
        XCTAssertEqual(relaunched.client?.accessToken, "secret-token")
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
