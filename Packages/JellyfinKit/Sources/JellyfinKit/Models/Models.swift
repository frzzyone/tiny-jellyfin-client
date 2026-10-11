import Foundation

public struct PublicSystemInfo: Codable, Sendable, Equatable {
    public var serverName: String?
    public var version: String?
    public var id: String?
    public var productName: String?
}

public struct UserDto: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var serverId: String?
}

public struct AuthenticationResult: Codable, Sendable {
    public var user: UserDto
    public var accessToken: String
    public var serverId: String?
}

public struct UserItemData: Codable, Sendable, Equatable {
    public var playbackPositionTicks: Int64?
    public var playedPercentage: Double?
    public var played: Bool?
    public var unplayedItemCount: Int?
}

public enum ItemKind: String, Codable, Sendable {
    case movie = "Movie"
    case series = "Series"
    case season = "Season"
    case episode = "Episode"
    case collectionFolder = "CollectionFolder"
    case userView = "UserView"
    case folder = "Folder"
    case boxSet = "BoxSet"
    case video = "Video"
    case other

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ItemKind(rawValue: raw) ?? .other
    }

    public var isPlayable: Bool { self == .movie || self == .episode || self == .video }
}

public struct BaseItem: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String?
    public var type: ItemKind?
    public var collectionType: String?
    public var productionYear: Int?
    public var premiereDate: String?
    public var runTimeTicks: Int64?
    public var overview: String?
    public var indexNumber: Int?
    public var parentIndexNumber: Int?
    public var seriesName: String?
    public var seriesId: String?
    public var seasonId: String?
    public var userData: UserItemData?
    public var imageTags: [String: String]?
    public var mediaSources: [MediaSourceInfo]?
    public var mediaStreams: [MediaStream]?

    public init(id: String, name: String? = nil, type: ItemKind? = nil) {
        self.id = id
        self.name = name
        self.type = type
    }

    public var displayName: String { name ?? "Untitled" }
    public var hasPrimaryImage: Bool { imageTags?["Primary"] != nil }

    /// Saved resume position, if the item is partly watched.
    public var resumePositionSeconds: Double? {
        guard let ticks = userData?.playbackPositionTicks, ticks > 0 else { return nil }
        return Ticks.seconds(ticks)
    }

    /// "S1 · E3"
    public var episodeLabel: String? {
        guard let episode = indexNumber else { return nil }
        if let season = parentIndexNumber { return "S\(season) · E\(episode)" }
        return "E\(episode)"
    }

    /// Year or air date for the details view.
    public var dateLabel: String? {
        if type == .episode, let date = premiereDate { return String(date.prefix(10)) }
        return productionYear.map(String.init)
    }
}

public struct ItemsResult: Codable, Sendable {
    public var items: [BaseItem]
    public var totalRecordCount: Int?
    public var startIndex: Int?
}

public enum MediaStreamType: String, Codable, Sendable {
    case video = "Video", audio = "Audio", subtitle = "Subtitle", embeddedImage = "EmbeddedImage", data = "Data"
    case other
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MediaStreamType(rawValue: raw) ?? .other
    }
}

public struct MediaStream: Codable, Sendable, Equatable {
    public var type: MediaStreamType
    public var index: Int
    public var codec: String?
    public var language: String?
    public var title: String?
    public var displayTitle: String?
    public var isExternal: Bool?
    public var isDefault: Bool?
    public var isForced: Bool?
    public var isTextSubtitleStream: Bool?
    public var deliveryMethod: String?
    public var deliveryUrl: String?
    public var height: Int?
    public var width: Int?
    public var bitRate: Int?
    public var videoRange: String?
    public var videoRangeType: String?

    public init(type: MediaStreamType, index: Int, codec: String? = nil) {
        self.type = type
        self.index = index
        self.codec = codec
    }

    /// Image-based subtitle formats that must be burned in by the server.
    public var isImageSubtitle: Bool {
        guard type == .subtitle else { return false }
        if let text = isTextSubtitleStream { return !text }
        return ["pgssub", "pgs", "dvdsub", "dvbsub", "vobsub", "xsub"].contains((codec ?? "").lowercased())
    }
}

public struct MediaSourceInfo: Codable, Sendable, Equatable {
    public var id: String?
    public var container: String?
    public var bitrate: Int?
    public var runTimeTicks: Int64?
    public var supportsDirectPlay: Bool?
    public var supportsDirectStream: Bool?
    public var supportsTranscoding: Bool?
    public var transcodingUrl: String?
    public var transcodingSubProtocol: String?
    public var mediaStreams: [MediaStream]?
    public var defaultAudioStreamIndex: Int?
    public var defaultSubtitleStreamIndex: Int?

    public var videoStream: MediaStream? { mediaStreams?.first { $0.type == .video } }
    public var subtitleStreams: [MediaStream] { mediaStreams?.filter { $0.type == .subtitle } ?? [] }
}

public struct PlaybackInfoResponse: Codable, Sendable {
    public var mediaSources: [MediaSourceInfo]
    public var playSessionId: String?
    public var errorCode: String?
}
