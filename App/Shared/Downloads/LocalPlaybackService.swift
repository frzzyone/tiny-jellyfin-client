import Foundation
import JellyfinKit

/// Plays a download: the same player, answered from the phone instead of the server. Reports go to
/// `onReport` (the progress queue), never straight to the server.
struct LocalPlaybackService: PlaybackService {
    let record: DownloadRecord
    let folder: URL
    /// Where the user is, when the phone knows better than the record (viewing not yet sent, or a
    /// fresher card from the server).
    var userData: UserItemData?
    /// Every progress tick and the stop (`stopped`), with the position.
    var onReport: @Sendable (_ itemId: String, _ positionSeconds: Double, _ stopped: Bool) -> Void

    var isDownloaded: Bool { true }
    var streamHeaders: [String: String] { [:] }
    var serverURL: URL { folder }

    func item(id: String) async throws -> BaseItem {
        var item = record.item
        if let userData { item.userData = userData }
        return item
    }

    func resolveStream(itemId: String, quality: QualityPreset, capabilities: PlaybackCapabilities,
                       startSeconds: Double, mediaSourceId: String?, subtitleStreamIndex: Int?,
                       audioStreamIndex: Int?) async throws -> ResolvedStream {
        guard let source = record.source else { throw JellyfinError.noPlayableStream(nil) }
        // A copy plays like a transcode: one audio track in the file, subtitles from files beside it.
        return ResolvedStream(url: folder.appendingPathComponent(record.mediaFile),
                              playMethod: record.isCopy ? .transcode : .directPlay, mediaSource: source,
                              mediaSourceId: source.id ?? itemId, playSessionId: nil, timelineOffset: record.timelineOffset)
    }

    func subtitleData(itemId: String, mediaSourceId: String, streamIndex: Int) async throws -> Data {
        try Data(contentsOf: folder.appendingPathComponent(Self.subtitleFile(streamIndex, picture: false)))
    }

    func pictureSubtitleData(itemId: String, mediaSourceId: String, streamIndex: Int, wait: TimeInterval) async throws -> Data {
        try Data(contentsOf: folder.appendingPathComponent(Self.subtitleFile(streamIndex, picture: true)))
    }

    func primaryImageURL(for item: BaseItem) -> URL? {
        let poster = folder.appendingPathComponent(Self.posterFile)
        return FileManager.default.fileExists(atPath: poster.path) ? poster : nil
    }

    func reportStart(_ report: PlaybackReport) async throws {}
    func reportProgress(_ report: PlaybackReport) async throws { onReport(report.itemId, Ticks.seconds(report.positionTicks), false) }
    func reportStopped(_ report: PlaybackReport) async throws { onReport(report.itemId, Ticks.seconds(report.positionTicks), true) }
    func endEncoding(playSessionId: String) async throws {}

    static let posterFile = "poster.jpg"
    static func subtitleFile(_ index: Int, picture: Bool) -> String { "sub-\(index).\(picture ? "sup" : "srt")" }
}
