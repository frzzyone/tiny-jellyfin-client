import Foundation

private let itemFields = "Overview,MediaSources,MediaStreams,PrimaryImageAspectRatio,PremiereDate,ProductionYear,DateCreated,Genres"

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

    // Quick Connect: the TV shows a code, the user approves it in another signed-in Jellyfin app.

    /// False when the server has Quick Connect turned off (it is off by default before 10.9).
    public func quickConnectEnabled() async throws -> Bool {
        try await get("/QuickConnect/Enabled")
    }

    public func initiateQuickConnect() async throws -> QuickConnectResult {
        try await post("/QuickConnect/Initiate", body: Empty())
    }

    /// The request's state; `authenticated` turns true once someone approves the code.
    public func quickConnectState(secret: String) async throws -> QuickConnectResult {
        try await get("/QuickConnect/Connect", query: ["secret": secret])
    }

    private struct QuickConnectAuthRequest: Encodable { var secret: String }

    public func authenticate(quickConnectSecret secret: String) async throws -> AuthenticationResult {
        let result: AuthenticationResult = try await post("/Users/AuthenticateWithQuickConnect",
                                                           body: QuickConnectAuthRequest(secret: secret))
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
        var query = ItemQuery(parentId: parentId)
        query.startIndex = startIndex
        query.limit = limit
        return try await items(query)
    }

    /// One page of items matching the query (see `ItemQuery`).
    public func items(_ query: ItemQuery) async throws -> ItemsResult {
        try await get("/Items", query: query.parameters(userId: try requireUserId()))
    }

    /// The next unwatched episode of every series the user has started, most recently watched first.
    public func nextUp(limit: Int = 24, seriesId: String? = nil) async throws -> [BaseItem] {
        let result: ItemsResult = try await get("/Shows/NextUp", query: [
            "userId": try requireUserId(), "limit": String(limit), "seriesId": seriesId,
            "fields": itemFields, "enableUserData": "true",
        ])
        return result.items
    }

    /// Newest additions, newest first; new episodes are grouped into their series.
    public func latest(limit: Int = 24) async throws -> [BaseItem] {
        try await get("/Items/Latest", query: [
            "userId": try requireUserId(), "limit": String(limit),
            "includeItemTypes": "Movie,Series,Episode", "fields": itemFields, "enableUserData": "true",
        ])
    }

    /// What the server thinks is like this item.
    public func similar(to itemId: String, limit: Int = 24) async throws -> [BaseItem] {
        let result: ItemsResult = try await get("/Items/\(itemId)/Similar", query: [
            "userId": try requireUserId(), "limit": String(limit), "fields": itemFields, "enableUserData": "true",
        ])
        return result.items
    }

    /// Genres present in the video libraries (or one library), by name.
    public func genres(libraryId: String? = nil) async throws -> [NameGuidPair] {
        let result: ItemsResult = try await get("/Genres", query: [
            "userId": try requireUserId(), "parentId": libraryId, "includeItemTypes": "Movie,Series",
            "sortBy": "SortName", "sortOrder": "Ascending",
        ])
        return result.items.map { NameGuidPair(id: $0.id, name: $0.name) }
    }

    /// Marks the item watched (or not) and returns its new user data.
    public func markPlayed(_ itemId: String, played: Bool) async throws -> UserItemData {
        let request = makeRequest(played ? "POST" : "DELETE", "/UserPlayedItems/\(itemId)",
                                  query: ["userId": try requireUserId()])
        return try decode(await send(request))
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

    /// Backdrop (wide artwork) of the item, or of its series for an episode.
    public func backdropImageURL(for item: BaseItem, maxWidth: Int = 1600) -> URL? {
        if let tag = item.backdropImageTags?.first {
            return url("/Items/\(item.id)/Images/Backdrop", query: ["maxWidth": String(maxWidth), "tag": tag, "quality": "90"])
        }
        if let parent = item.parentBackdropItemId, let tag = item.parentBackdropImageTags?.first {
            return url("/Items/\(parent)/Images/Backdrop", query: ["maxWidth": String(maxWidth), "tag": tag, "quality": "90"])
        }
        return nil
    }
}

/// A `/Items` query: which items, filtered and sorted how, one page at a time.
public struct ItemQuery: Equatable, Sendable {
    public enum Sort: String, Sendable { case name = "SortName", dateCreated = "DateCreated", datePlayed = "DatePlayed",
                                        random = "Random", premiereDate = "PremiereDate" }
    public enum Filter: String, Sendable { case unplayed = "IsUnplayed", played = "IsPlayed", resumable = "IsResumable" }

    public var parentId: String?
    public var types: [ItemKind] = [.movie, .series]
    public var filters: [Filter] = []
    public var sort: Sort = .name
    public var descending = false
    public var genreIds: [String] = []
    public var years: [Int] = []
    public var searchTerm: String?
    public var startIndex = 0
    public var limit = 60

    public init(parentId: String? = nil, types: [ItemKind] = [.movie, .series], filters: [Filter] = [],
                sort: Sort = .name, descending: Bool = false, limit: Int = 60) {
        self.parentId = parentId
        self.types = types
        self.filters = filters
        self.sort = sort
        self.descending = descending
        self.limit = limit
    }

    func parameters(userId: String) -> [String: String?] {
        let term = searchTerm?.trimmingCharacters(in: .whitespaces)
        return [
            "userId": userId, "parentId": parentId, "recursive": "true",
            "includeItemTypes": types.map(\.rawValue).joined(separator: ","),
            "filters": filters.isEmpty ? nil : filters.map(\.rawValue).joined(separator: ","),
            "sortBy": sort.rawValue, "sortOrder": descending ? "Descending" : "Ascending",
            "genreIds": genreIds.isEmpty ? nil : genreIds.joined(separator: ","),
            "years": years.isEmpty ? nil : years.map(String.init).joined(separator: ","),
            "searchTerm": (term?.isEmpty ?? true) ? nil : term,
            "startIndex": String(startIndex), "limit": String(limit),
            "fields": itemFields, "enableUserData": "true",
        ]
    }
}
