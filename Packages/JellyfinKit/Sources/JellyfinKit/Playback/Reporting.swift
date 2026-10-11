import Foundation

public struct PlaybackReport: Codable, Sendable, Equatable {
    public var itemId: String
    public var mediaSourceId: String
    public var playSessionId: String?
    public var positionTicks: Int64
    public var isPaused: Bool
    public var playMethod: String
    public var canSeek: Bool
    public var subtitleStreamIndex: Int?
    public var eventName: String?

    public init(itemId: String, mediaSourceId: String, playSessionId: String?, positionSeconds: Double,
                isPaused: Bool, playMethod: PlayMethod, subtitleStreamIndex: Int? = nil, eventName: String? = nil) {
        self.itemId = itemId
        self.mediaSourceId = mediaSourceId
        self.playSessionId = playSessionId
        self.positionTicks = Ticks.from(seconds: positionSeconds)
        self.isPaused = isPaused
        self.playMethod = playMethod.rawValue
        self.canSeek = true
        self.subtitleStreamIndex = subtitleStreamIndex
        self.eventName = eventName
    }
}

/// Abstraction used by the playback controller so it can be tested without a server.
public protocol PlaybackReporter: Sendable {
    func reportStart(_ report: PlaybackReport) async throws
    func reportProgress(_ report: PlaybackReport) async throws
    func reportStopped(_ report: PlaybackReport) async throws
    func endEncoding(playSessionId: String) async throws
}

extension JellyfinClient: PlaybackReporter {
    public func reportStart(_ report: PlaybackReport) async throws {
        try await postNoContent("/Sessions/Playing", body: report)
    }

    public func reportProgress(_ report: PlaybackReport) async throws {
        try await postNoContent("/Sessions/Playing/Progress", body: report)
    }

    public func reportStopped(_ report: PlaybackReport) async throws {
        try await postNoContent("/Sessions/Playing/Stopped", body: report)
    }

    /// Ends the server transcoding job for a play session.
    public func endEncoding(playSessionId: String) async throws {
        try await send("DELETE", "/Videos/ActiveEncodings", query: [
            "deviceId": identity.deviceId, "playSessionId": playSessionId,
        ])
    }
}
