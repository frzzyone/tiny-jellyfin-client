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

public struct QuickConnectResult: Codable, Sendable, Equatable {
    public var authenticated: Bool
    public var secret: String
    public var code: String
}

public struct UserItemData: Codable, Sendable, Equatable {
    public var playbackPositionTicks: Int64?
    public var playedPercentage: Double?
    public var played: Bool?
    public var unplayedItemCount: Int?
    /// ISO 8601, set once the user has played any of the item.
    public var lastPlayedDate: String?

    public init(playbackPositionTicks: Int64? = nil, playedPercentage: Double? = nil, played: Bool? = nil,
                unplayedItemCount: Int? = nil, lastPlayedDate: String? = nil) {
        self.playbackPositionTicks = playbackPositionTicks
        self.playedPercentage = playedPercentage
        self.played = played
        self.unplayedItemCount = unplayedItemCount
        self.lastPlayedDate = lastPlayedDate
    }
}

/// A genre, studio or person reference on an item.
public struct NameGuidPair: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String?

    public init(id: String, name: String?) {
        self.id = id
        self.name = name
    }
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
    public var backdropImageTags: [String]?
    public var parentBackdropItemId: String?
    public var parentBackdropImageTags: [String]?
    /// ISO 8601; when the item was added to the library.
    public var dateCreated: String?
    public var genres: [String]?
    public var genreItems: [NameGuidPair]?
    public var mediaSources: [MediaSourceInfo]?
    public var mediaStreams: [MediaStream]?

    public init(id: String, name: String? = nil, type: ItemKind? = nil) {
        self.id = id
        self.name = name
        self.type = type
    }

    /// Runtime in whole minutes.
    public var runtimeMinutes: Int? {
        runTimeTicks.map { Int((Ticks.seconds($0) / 60).rounded()) }
    }

    /// Seconds still to watch for a partly watched item.
    public var remainingSeconds: Double? {
        guard let ticks = runTimeTicks, let position = resumePositionSeconds else { return nil }
        return max(0, Ticks.seconds(ticks) - position)
    }

    /// "4K", "HDR10", "Dolby Vision", "Atmos", "7.1": what the file is, from its media streams.
    public var formatBadges: [String] { FormatBadges.badges(for: mediaStreams ?? mediaSources?.first?.mediaStreams ?? []) }

    public var displayName: String { name ?? "Untitled" }

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

    public init(items: [BaseItem], totalRecordCount: Int?, startIndex: Int?) {
        self.items = items
        self.totalRecordCount = totalRecordCount
        self.startIndex = startIndex
    }
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
    public var profile: String?
    public var channels: Int?

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
    public var audioStreams: [MediaStream] { mediaStreams?.filter { $0.type == .audio } ?? [] }
}

public struct PlaybackInfoResponse: Codable, Sendable {
    public var mediaSources: [MediaSourceInfo]
    public var playSessionId: String?
    public var errorCode: String?
}

public enum FormatBadges {
    public static func badges(for streams: [MediaStream]) -> [String] {
        var badges: [String] = []
        if let video = streams.first(where: { $0.type == .video }) {
            if let width = video.width, width >= 3200 { badges.append("4K") }
            else if let height = video.height, height >= 1080 { badges.append("1080p") }
            let range = (video.videoRangeType ?? video.videoRange ?? "").uppercased()
            if range.hasPrefix("DOVI") { badges.append("Dolby Vision") }
            else if range.contains("HDR10+") { badges.append("HDR10+") }
            else if range.contains("HDR10") { badges.append("HDR10") }
            else if range.contains("HLG") { badges.append("HLG") }
            else if range.contains("HDR") { badges.append("HDR") }
        }
        if let audio = streams.first(where: { $0.type == .audio }) {
            let text = [audio.profile, audio.displayTitle, audio.title].compactMap { $0 }.joined(separator: " ").lowercased()
            if text.contains("atmos") { badges.append("Atmos") }
            else if let channels = audio.channels, channels >= 6 { badges.append(channels >= 8 ? "7.1" : "5.1") }
        }
        return badges
    }
}

/// Navigation values (a title's page) are items; equal items have equal ids, so hashing the id is enough.
extension BaseItem: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
