import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JellyfinKit

final class ServerEndpointTests: XCTestCase {
    func testPublicSystemInfo() async throws {
        let server = StubServer()
        server.on("GET", "/System/Info/Public", json: #"{"ServerName":"Home","Version":"10.10.3","Id":"abc"}"#)
        let info = try await server.client(token: nil).publicSystemInfo()
        XCTAssertEqual(info.serverName, "Home")
    }

    func testNonJellyfinServer() async {
        let server = StubServer()
        server.on("GET", "/System/Info/Public", status: 200, json: "<html>hello</html>")
        do {
            _ = try await server.client(token: nil).publicSystemInfo()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? JellyfinError, .notJellyfin)
        }
    }

    func testAuthenticateSetsCredentials() async throws {
        let server = StubServer()
        server.on("POST", "/Users/AuthenticateByName",
                  json: #"{"User":{"Id":"u42","Name":"frank"},"AccessToken":"secret-token","ServerId":"s"}"#)
        let client = server.client(token: nil, userId: nil)
        let result = try await client.authenticate(username: "frank", password: "hunter2")
        XCTAssertEqual(result.user.id, "u42")
        XCTAssertEqual(client.accessToken, "secret-token")
        XCTAssertEqual(client.userId, "u42")
        let body = jsonBody(server.lastRequest(path: "/Users/AuthenticateByName"))
        XCTAssertEqual(body["Username"] as? String, "frank")
        XCTAssertEqual(body["Pw"] as? String, "hunter2")
    }

    func testWrongCredentials() async {
        let server = StubServer()
        server.on("POST", "/Users/AuthenticateByName", status: 401, json: "")
        do {
            _ = try await server.client(token: nil, userId: nil).authenticate(username: "a", password: "b")
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? JellyfinError, .unauthorized)
        }
    }

    func testLogout() async throws {
        let server = StubServer()
        server.on("POST", "/Sessions/Logout", status: 204, json: "")
        try await server.client().logout()
        XCTAssertNotNil(server.lastRequest(path: "/Sessions/Logout"))
    }
}

final class BrowsingEndpointTests: XCTestCase {
    func testLibrariesFilteredToVideo() async throws {
        let server = StubServer()
        server.on("GET", "/UserViews", json: """
        {"Items":[
          {"Id":"1","Name":"Movies","CollectionType":"movies","Type":"CollectionFolder"},
          {"Id":"2","Name":"Music","CollectionType":"music","Type":"CollectionFolder"},
          {"Id":"3","Name":"Shows","CollectionType":"tvshows","Type":"CollectionFolder"},
          {"Id":"4","Name":"Live TV","CollectionType":"livetv","Type":"UserView"},
          {"Id":"5","Name":"Books","CollectionType":"books","Type":"CollectionFolder"}
        ],"TotalRecordCount":5}
        """)
        let libraries = try await server.client().libraries()
        XCTAssertEqual(libraries.map(\.name), ["Movies", "Shows"])
        XCTAssertEqual(queryValue(server.lastRequest(path: "/UserViews"), "userId"), "user1")
    }

    func testResumeItems() async throws {
        let server = StubServer()
        server.on("GET", "/UserItems/Resume", json: """
        {"Items":[{"Id":"m","Name":"Movie","Type":"Movie","UserData":{"PlaybackPositionTicks":25300000000,"PlayedPercentage":50.2}}]}
        """)
        let items = try await server.client().resumeItems()
        XCTAssertEqual(items.first?.resumePositionSeconds, 2530)
        XCTAssertEqual(items.first?.userData?.playedPercentage ?? 0, 50.2, accuracy: 0.01)
        XCTAssertEqual(queryValue(server.lastRequest(path: "/UserItems/Resume"), "mediaTypes"), "Video")
    }

    func testItemsPaging() async throws {
        let server = StubServer()
        server.on("GET", "/Items", json: #"{"Items":[{"Id":"a","Name":"Alien","Type":"Movie"}],"TotalRecordCount":321,"StartIndex":100}"#)
        let page = try await server.client().items(parentId: "lib", startIndex: 100, limit: 50)
        XCTAssertEqual(page.totalRecordCount, 321)
        let request = server.lastRequest(path: "/Items")
        XCTAssertEqual(queryValue(request, "parentId"), "lib")
        XCTAssertEqual(queryValue(request, "startIndex"), "100")
        XCTAssertEqual(queryValue(request, "limit"), "50")
        XCTAssertEqual(queryValue(request, "sortBy"), "SortName")
    }

    func testSeasonsAndEpisodesInOrder() async throws {
        let server = StubServer()
        server.on("GET", "/Shows/s1/Seasons", json: #"{"Items":[{"Id":"se1","Name":"Season 1","Type":"Season","IndexNumber":1}]}"#)
        server.on("GET", "/Shows/s1/Episodes", json: """
        {"Items":[
          {"Id":"e2","Name":"Two","Type":"Episode","IndexNumber":2,"ParentIndexNumber":1,"UserData":{"Played":false}},
          {"Id":"e1","Name":"One","Type":"Episode","IndexNumber":1,"ParentIndexNumber":1,"UserData":{"Played":true}}
        ]}
        """)
        let client = server.client()
        let seasons = try await client.seasons(seriesId: "s1")
        XCTAssertEqual(seasons.map(\.id), ["se1"])
        let episodes = try await client.episodes(seriesId: "s1", seasonId: "se1")
        XCTAssertEqual(episodes.map(\.id), ["e1", "e2"])
        XCTAssertEqual(episodes.first?.episodeLabel, "S1 · E1")
        XCTAssertEqual(episodes.first?.userData?.played, true)
        XCTAssertEqual(queryValue(server.lastRequest(path: "/Shows/s1/Episodes"), "seasonId"), "se1")
    }

    func testItemDetailsDecodeMediaStreams() async throws {
        let server = StubServer()
        server.on("GET", "/Items/m1", json: """
        {"Id":"m1","Name":"Movie","Type":"Movie","ProductionYear":2019,"RunTimeTicks":67200000000,
         "MediaSources":[{"Id":"src","Container":"mkv","MediaStreams":[
            {"Type":"Video","Index":0,"Codec":"hevc","Height":2160,"Width":3840,"VideoRangeType":"DOVIWithHDR10"},
            {"Type":"Audio","Index":1,"Codec":"eac3"},
            {"Type":"Subtitle","Index":2,"Codec":"subrip","Language":"eng","IsTextSubtitleStream":true},
            {"Type":"Subtitle","Index":3,"Codec":"PGSSUB","Language":"spa","IsTextSubtitleStream":false},
            {"Type":"Attachment","Index":4}
         ]}]}
        """)
        let item = try await server.client().item(id: "m1")
        XCTAssertEqual(item.dateLabel, "2019")
        let source = try XCTUnwrap(item.mediaSources?.first)
        XCTAssertEqual(source.videoStream?.height, 2160)
        XCTAssertEqual(source.subtitleStreams.map(\.isImageSubtitle), [false, true])
        XCTAssertEqual(source.mediaStreams?.last?.type, .other)
    }

    func testImageURL() {
        let server = StubServer()
        var item = BaseItem(id: "m1", name: "M", type: .movie)
        XCTAssertNil(server.client().primaryImageURL(for: item))
        item.imageTags = ["Primary": "tag1"]
        let url = server.client().primaryImageURL(for: item, maxHeight: 300)
        XCTAssertEqual(url?.path, "/Items/m1/Images/Primary")
        XCTAssertEqual(url?.query?.contains("maxHeight=300"), true)
    }
}
