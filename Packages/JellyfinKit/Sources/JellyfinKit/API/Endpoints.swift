import Foundation

private let itemFields = "Overview,MediaSources,MediaStreams,PrimaryImageAspectRatio,PremiereDate,ProductionYear"

extension JellyfinClient {
    // MARK: Server & auth

    public func publicSystemInfo() async throws -> PublicSystemInfo {
        let info: PublicSystemInfo
        do {
            info = try await get("/System/Info/Public")
        } catch JellyfinError.decoding {
            throw JellyfinError.notJellyfin
        } catch JellyfinError.server {
            throw JellyfinError.notJellyfin
        }
        guard info.id != nil || info.version != nil else { throw JellyfinError.notJellyfin }
        return info
    }

    private struct AuthRequest: Encodable { var username: String; var pw: String }

    public func authenticate(username: String, password: String) async throws -> AuthenticationResult {
        let result: AuthenticationResult = try await post("/Users/AuthenticateByName",
                                                           body: AuthRequest(username: username, pw: password))
        setCredentials(token: result.accessToken, userId: result.user.id)
        return result
    }

    public func logout() async throws {
        try await send("POST", "/Sessions/Logout")
    }

    // MARK: Browsing

    public static let supportedCollectionTypes: Set<String> = ["movies", "tvshows"]

    /// Video libraries the user can see, in server order (music, books, live TV removed).
    public func libraries() async throws -> [BaseItem] {
        let result: ItemsResult = try await get("/UserViews", query: ["userId": try requireUserId()])
        return result.items.filter { Self.supportedCollectionTypes.contains(($0.collectionType ?? "").lowercased()) }
    }

    public func resumeItems(limit: Int = 24) async throws -> [BaseItem] {
        let result: ItemsResult = try await get("/UserItems/Resume", query: [
            "userId": try requireUserId(), "mediaTypes": "Video", "limit": String(limit),
            "fields": itemFields, "enableUserData": "true",
        ])
        return result.items
    }

    /// One page of a library's top-level items, sorted by name.
    public func items(parentId: String, startIndex: Int, limit: Int) async throws -> ItemsResult {
        try await get("/Items", query: [
            "userId": try requireUserId(), "parentId": parentId,
            "sortBy": "SortName", "sortOrder": "Ascending",
            "includeItemTypes": "Movie,Series", "recursive": "true",
            "startIndex": String(startIndex), "limit": String(limit),
            "fields": "PrimaryImageAspectRatio,ProductionYear", "enableUserData": "true",
        ])
    }

    public func seasons(seriesId: String) async throws -> [BaseItem] {
        let result: ItemsResult = try await get("/Shows/\(seriesId)/Seasons", query: [
            "userId": try requireUserId(), "enableUserData": "true",
        ])
        return result.items
    }

    public func episodes(seriesId: String, seasonId: String) async throws -> [BaseItem] {
        let result: ItemsResult = try await get("/Shows/\(seriesId)/Episodes", query: [
            "userId": try requireUserId(), "seasonId": seasonId, "fields": itemFields, "enableUserData": "true",
        ])
        return result.items.sorted { ($0.indexNumber ?? 0) < ($1.indexNumber ?? 0) }
    }

    public func item(id: String) async throws -> BaseItem {
        try await get("/Items/\(id)", query: ["userId": try requireUserId()])
    }

    /// Primary image URL. Images are public for authenticated sessions via the tag.
    public func primaryImageURL(for item: BaseItem, maxHeight: Int = 450) -> URL? {
        guard let tag = item.imageTags?["Primary"] else { return nil }
        return url("/Items/\(item.id)/Images/Primary", query: ["maxHeight": String(maxHeight), "tag": tag, "quality": "90"])
    }
}
