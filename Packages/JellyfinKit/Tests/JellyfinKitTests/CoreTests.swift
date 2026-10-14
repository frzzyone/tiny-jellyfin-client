import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JellyfinKit

final class ClientIdentityTests: XCTestCase {
    func testHeaderWithoutToken() {
        let header = ClientIdentity.test.authorizationHeader(token: nil)
        XCTAssertEqual(header, #"MediaBrowser Client="Kinema", Device="Test%20Mac", DeviceId="device-1", Version="0.1.0""#)
    }

    func testHeaderWithToken() {
        let header = ClientIdentity.test.authorizationHeader(token: "abc123")
        XCTAssertTrue(header.hasSuffix(#", Token="abc123""#))
    }

    func testEmptyTokenIsOmitted() {
        XCTAssertFalse(ClientIdentity.test.authorizationHeader(token: "").contains("Token="))
    }

    func testValuesAreEscaped() {
        let identity = ClientIdentity(device: #"Frank's "Mac", Pro é"#, deviceId: "d", version: "1")
        let header = identity.authorizationHeader(token: nil)
        XCTAssertTrue(header.contains(#"Device="Frank%27s%20%22Mac%22%2C%20Pro%20%C3%A9""#), header)
        // Only the structural quotes remain.
        XCTAssertEqual(header.filter { $0 == "\"" }.count, 8)
    }
}

final class ServerAddressTests: XCTestCase {
    func n(_ s: String) throws -> String { try ServerAddress.normalize(s).absoluteString }

    func testPlainHTTPFallbackOnlyWithoutAScheme() {
        XCTAssertEqual(ServerAddress.plainHTTPFallback(for: " media.lan:8096/jf/ ")?.absoluteString, "http://media.lan:8096/jf")
        XCTAssertNil(ServerAddress.plainHTTPFallback(for: "https://media.lan"))
        XCTAssertNil(ServerAddress.plainHTTPFallback(for: "http://media.lan"))
    }

    func testServerErrorPagesAreNotShownAsMessages() {
        XCTAssertEqual(JellyfinClient.readableMessage(Data("Item not found".utf8)), "Item not found")
        XCTAssertNil(JellyfinClient.readableMessage(Data("<html><body>502 Bad Gateway</body></html>".utf8)))
        XCTAssertNil(JellyfinClient.readableMessage(Data("System.Exception: boom\n   at Jellyfin.Api…".utf8)))
        XCTAssertNil(JellyfinClient.readableMessage(Data()))
    }

    func testAddsHTTPSWhenNoScheme() throws {
        XCTAssertEqual(try n("media.example.com:8096"), "https://media.example.com:8096")
    }

    func testKeepsExplicitHTTP() throws {
        XCTAssertEqual(try n("http://192.168.1.10:8096"), "http://192.168.1.10:8096")
    }

    func testStripsTrailingSlashesAndKeepsPath() throws {
        XCTAssertEqual(try n("https://example.com/jellyfin///"), "https://example.com/jellyfin")
        XCTAssertEqual(try n("  example.com/  "), "https://example.com")
    }

    func testUppercaseSchemeIsAccepted() throws {
        XCTAssertEqual(try n("HTTP://example.com"), "http://example.com")
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try n(""))
        XCTAssertThrowsError(try n("not a url"))
        XCTAssertThrowsError(try n("ftp://example.com"))
        XCTAssertThrowsError(try n("https://"))
    }
}

final class TicksTests: XCTestCase {
    func testConversion() {
        XCTAssertEqual(Ticks.from(seconds: 1.5), 15_000_000)
        XCTAssertEqual(Ticks.seconds(25_300_000_000), 2530)
        XCTAssertEqual(Ticks.from(seconds: -3), 0)
        XCTAssertEqual(Ticks.from(seconds: .nan), 0)
    }

    func testClockFormatting() {
        XCTAssertEqual(TimeFormat.clock(2530), "42:10")
        XCTAssertEqual(TimeFormat.clock(3750), "1:02:30")
        XCTAssertEqual(TimeFormat.clock(5), "0:05")
        XCTAssertEqual(TimeFormat.runtime(ticks: 6_720 * Ticks.perSecond), "1h 52m")
        XCTAssertEqual(TimeFormat.runtime(ticks: 2_880 * Ticks.perSecond), "48m")
    }
}

final class ClientPlumbingTests: XCTestCase {
    func testURLJoiningKeepsBasePath() {
        let server = StubServer(basePath: "/jellyfin")
        let url = server.client().url("/Items", query: ["b": "2", "a": "1", "skip": nil])
        XCTAssertEqual(url.absoluteString, "\(server.baseURL.absoluteString)/Items?a=1&b=2")
    }

    func testResolveServerRelative() {
        let server = StubServer(basePath: "/jf")
        let url = server.client().resolve(serverRelative: "/videos/abc/master.m3u8?MediaSourceId=x&ApiKey=k")
        XCTAssertEqual(url?.absoluteString, "\(server.baseURL.absoluteString)/videos/abc/master.m3u8?MediaSourceId=x&ApiKey=k")
    }

    func testRequestsCarryAuthorization() async throws {
        let server = StubServer()
        server.on("GET", "/Items/x", json: #"{"Id":"x","Name":"X"}"#)
        _ = try await server.client().item(id: "x")
        let header = server.lastRequest(path: "/Items/x")?.value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(header, ClientIdentity.test.authorizationHeader(token: "tok"))
    }

    func testUnauthorizedMapsAndNotifies() async {
        let server = StubServer()
        server.on("GET", "/Items/x", status: 401, json: "")
        let client = server.client()
        let expectation = expectation(description: "onUnauthorized")
        client.onUnauthorized = { expectation.fulfill() }
        do {
            _ = try await client.item(id: "x")
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? JellyfinError, .unauthorized)
        }
        await fulfillment(of: [expectation], timeout: 2)
    }

    func testServerError() async {
        let server = StubServer()
        server.on("GET", "/Items/x", status: 500, json: "boom")
        do {
            _ = try await server.client().item(id: "x")
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? JellyfinError, .server(status: 500, message: "boom"))
        }
    }

    func testDecodingError() async {
        let server = StubServer()
        server.on("GET", "/Items/x", json: #"{"Nope":1}"#)
        do {
            _ = try await server.client().item(id: "x")
            XCTFail("expected error")
        } catch {
            guard case .decoding = error as? JellyfinError else { return XCTFail("\(error)") }
        }
    }

    func testNetworkError() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let client = JellyfinClient(baseURL: URL(string: "https://unrouted.test")!, identity: .test,
                                    accessToken: "t", userId: "u", session: URLSession(configuration: config))
        do {
            _ = try await client.item(id: "x")
            XCTFail("expected error")
        } catch {
            guard case .network = error as? JellyfinError else { return XCTFail("\(error)") }
        }
    }
}
