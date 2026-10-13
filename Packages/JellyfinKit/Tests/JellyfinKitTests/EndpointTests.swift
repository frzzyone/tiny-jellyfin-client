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
        var query = ItemQuery(parentId: "lib", limit: 50)
        query.startIndex = 100
        let page = try await server.client().items(query)
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
         ]}],
         "Chapters":[{"StartPositionTicks":0,"Name":"Opening"},{"StartPositionTicks":3000000000,"Name":"The Heist"}]}
        """)
        let item = try await server.client().item(id: "m1")
        XCTAssertEqual(item.dateLabel, "2019")
        let source = try XCTUnwrap(item.mediaSources?.first)
        XCTAssertEqual(source.videoStream?.height, 2160)
        XCTAssertEqual(source.subtitleStreams.map(\.isImageSubtitle), [false, true])
        XCTAssertEqual(source.mediaStreams?.last?.type, .other)
        XCTAssertEqual(item.chapters?.map(\.name), ["Opening", "The Heist"])
        XCTAssertEqual(item.chapters?.last?.startSeconds, 300)
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

final class DiscoveryEndpointTests: XCTestCase {
    func testItemQueryEncodesFiltersSortGenresYearsAndSearch() async throws {
        let server = StubServer()
        server.on("GET", "/Items", json: #"{"Items":[],"TotalRecordCount":0}"#)
        var query = ItemQuery(parentId: "lib", types: [.movie], filters: [.unplayed], sort: .dateCreated, descending: true, limit: 24)
        query.genreIds = ["g1", "g2"]
        query.years = [1990, 1991]
        query.searchTerm = "  he "
        query.startIndex = 48
        _ = try await server.client().items(query)
        let request = server.lastRequest(path: "/Items")
        XCTAssertEqual(queryValue(request, "includeItemTypes"), "Movie")
        XCTAssertEqual(queryValue(request, "filters"), "IsUnplayed")
        XCTAssertEqual(queryValue(request, "sortBy"), "DateCreated")
        XCTAssertEqual(queryValue(request, "sortOrder"), "Descending")
        XCTAssertEqual(queryValue(request, "genreIds"), "g1,g2")
        XCTAssertEqual(queryValue(request, "years"), "1990,1991")
        XCTAssertEqual(queryValue(request, "searchTerm"), "he")
        XCTAssertEqual(queryValue(request, "startIndex"), "48")
        XCTAssertEqual(queryValue(request, "limit"), "24")
        XCTAssertEqual(queryValue(request, "recursive"), "true")
        XCTAssertTrue(queryValue(request, "fields")?.contains("DateCreated") == true)
    }

    func testItemQueryOmitsEmptyParts() async throws {
        let server = StubServer()
        server.on("GET", "/Items", json: #"{"Items":[]}"#)
        var query = ItemQuery()
        query.searchTerm = "   "
        _ = try await server.client().items(query)
        let request = server.lastRequest(path: "/Items")
        XCTAssertNil(queryValue(request, "filters"))
        XCTAssertNil(queryValue(request, "genreIds"))
        XCTAssertNil(queryValue(request, "years"))
        XCTAssertNil(queryValue(request, "searchTerm"))
        XCTAssertNil(queryValue(request, "parentId"))
        XCTAssertEqual(queryValue(request, "includeItemTypes"), "Movie,Series")
    }

    func testNextUp() async throws {
        let server = StubServer()
        server.on("GET", "/Shows/NextUp", json: """
        {"Items":[{"Id":"e4","Name":"Woe's Hollow","Type":"Episode","SeriesName":"Severance","IndexNumber":4,"ParentIndexNumber":2,
                   "ParentBackdropItemId":"s1","ParentBackdropImageTags":["bt"]}]}
        """)
        let items = try await server.client().nextUp(limit: 10, seriesId: "s1")
        XCTAssertEqual(items.first?.episodeLabel, "S2 · E4")
        let request = server.lastRequest(path: "/Shows/NextUp")
        XCTAssertEqual(queryValue(request, "seriesId"), "s1")
        XCTAssertEqual(queryValue(request, "limit"), "10")
        XCTAssertEqual(queryValue(request, "userId"), "user1")
        let backdrop = server.client().backdropImageURL(for: items[0])
        XCTAssertEqual(backdrop?.path, "/Items/s1/Images/Backdrop")
        XCTAssertEqual(queryValue(backdrop.map { URLRequest(url: $0) }, "tag"), "bt")
    }

    func testLatestIsAPlainArray() async throws {
        let server = StubServer()
        server.on("GET", "/Items/Latest", json: #"[{"Id":"n","Name":"New","Type":"Movie","DateCreated":"2026-10-10T08:00:00.0000000Z"}]"#)
        let items = try await server.client().latest(limit: 5)
        XCTAssertEqual(items.map(\.id), ["n"])
        XCTAssertEqual(items[0].dateCreated, "2026-10-10T08:00:00.0000000Z")
        XCTAssertEqual(queryValue(server.lastRequest(path: "/Items/Latest"), "includeItemTypes"), "Movie,Series,Episode")
    }

    func testSimilarAndGenres() async throws {
        let server = StubServer()
        server.on("GET", "/Items/heat/Similar", json: #"{"Items":[{"Id":"c","Name":"Collateral","Type":"Movie"}]}"#)
        server.on("GET", "/Genres", json: #"{"Items":[{"Id":"g1","Name":"Thriller","Type":"Genre"},{"Id":"g2","Name":"Comedy","Type":"Genre"}]}"#)
        let client = server.client()
        let similar = try await client.similar(to: "heat")
        XCTAssertEqual(similar.map(\.name), ["Collateral"])
        let genres = try await client.genres(libraryId: "lib")
        XCTAssertEqual(genres.map(\.name), ["Thriller", "Comedy"])
        XCTAssertEqual(queryValue(server.lastRequest(path: "/Genres"), "parentId"), "lib")
    }

    func testMarkPlayedAndUnplayed() async throws {
        let server = StubServer()
        server.on("POST", "/UserPlayedItems/m", json: #"{"Played":true,"PlayedPercentage":100}"#)
        server.on("DELETE", "/UserPlayedItems/m", json: #"{"Played":false}"#)
        let client = server.client()
        let played = try await client.markPlayed("m", played: true)
        XCTAssertEqual(played.played, true)
        let unplayed = try await client.markPlayed("m", played: false)
        XCTAssertEqual(unplayed.played, false)
        XCTAssertEqual(server.lastRequest(path: "/UserPlayedItems/m")?.httpMethod, "DELETE")
    }

    func testBackdropFallsBackToParentOrNothing() {
        let server = StubServer()
        var own = BaseItem(id: "x")
        own.backdropImageTags = ["t1"]
        XCTAssertEqual(server.client().backdropImageURL(for: own)?.path, "/Items/x/Images/Backdrop")
        XCTAssertNil(server.client().backdropImageURL(for: BaseItem(id: "y")))
    }
}

final class FormatBadgeTests: XCTestCase {
    private func stream(_ type: MediaStreamType, width: Int? = nil, height: Int? = nil, range: String? = nil,
                        profile: String? = nil, channels: Int? = nil) -> MediaStream {
        var s = MediaStream(type: type, index: 0)
        s.width = width; s.height = height; s.videoRangeType = range; s.profile = profile; s.channels = channels
        return s
    }

    func testBadges() {
        XCTAssertEqual(FormatBadges.badges(for: [stream(.video, width: 3840, height: 2160, range: "DOVIWithHDR10"),
                                                  stream(.audio, profile: "Dolby Atmos", channels: 8)]),
                       ["4K", "Dolby Vision", "Atmos"])
        XCTAssertEqual(FormatBadges.badges(for: [stream(.video, width: 1920, height: 1080, range: "SDR"),
                                                  stream(.audio, channels: 6)]), ["1080p", "5.1"])
        XCTAssertEqual(FormatBadges.badges(for: [stream(.video, width: 1280, height: 720, range: "HDR10"),
                                                  stream(.audio, channels: 2)]), ["HDR10"])
        XCTAssertEqual(FormatBadges.badges(for: []), [])
    }

    func testItemConveniences() {
        var item = BaseItem(id: "i")
        item.runTimeTicks = 6_000_000_000 // 10 min
        item.userData = UserItemData(playbackPositionTicks: 1_200_000_000)
        XCTAssertEqual(item.runtimeMinutes, 10)
        XCTAssertEqual(item.remainingSeconds, 480)
        XCTAssertNil(BaseItem(id: "j").remainingSeconds)
    }
}
