import Foundation
import JellyfinKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Server calls the playback controller needs, so tests can replace the server.
protocol PlaybackService: PlaybackReporter {
    var streamHeaders: [String: String] { get }
    var serverURL: URL { get }
    func item(id: String) async throws -> BaseItem
    func resolveStream(itemId: String, quality: QualityPreset, capabilities: PlaybackCapabilities,
                       startSeconds: Double, mediaSourceId: String?, subtitleStreamIndex: Int?,
                       audioStreamIndex: Int?) async throws -> ResolvedStream
    /// Downloads a text subtitle track converted to SRT by the server.
    func subtitleData(itemId: String, mediaSourceId: String, streamIndex: Int) async throws -> Data
    /// Downloads a picture subtitle track as the `.sup` the server extracted. Fails when the server
    /// sends nothing for `wait` seconds: it is still extracting the track from the file.
    func pictureSubtitleData(itemId: String, mediaSourceId: String, streamIndex: Int, wait: TimeInterval) async throws -> Data
    func primaryImageURL(for item: BaseItem) -> URL?
}

struct JellyfinPlaybackService: PlaybackService {
    let client: JellyfinClient

    var streamHeaders: [String: String] { ["Authorization": client.authorizationHeaderValue] }
    var serverURL: URL { client.baseURL }

    func item(id: String) async throws -> BaseItem { try await client.item(id: id) }

    func resolveStream(itemId: String, quality: QualityPreset, capabilities: PlaybackCapabilities,
                       startSeconds: Double, mediaSourceId: String?, subtitleStreamIndex: Int?,
                       audioStreamIndex: Int?) async throws -> ResolvedStream {
        let response = try await client.playbackInfo(itemId: itemId, quality: quality, capabilities: capabilities,
                                                     startSeconds: startSeconds, mediaSourceId: mediaSourceId,
                                                     subtitleStreamIndex: subtitleStreamIndex,
                                                     audioStreamIndex: audioStreamIndex)
        return try client.resolveStream(itemId: itemId, response: response, startSeconds: startSeconds)
    }

    func subtitleData(itemId: String, mediaSourceId: String, streamIndex: Int) async throws -> Data {
        try await download(URLRequest(url: client.externalSubtitleURL(itemId: itemId, mediaSourceId: mediaSourceId,
                                                                      streamIndex: streamIndex)))
    }

    func pictureSubtitleData(itemId: String, mediaSourceId: String, streamIndex: Int, wait: TimeInterval) async throws -> Data {
        // An idle timeout, not a deadline: a long download is fine as long as bytes keep coming.
        try await download(URLRequest(url: client.externalSubtitleURL(itemId: itemId, mediaSourceId: mediaSourceId,
                                                                      streamIndex: streamIndex, format: "sup"),
                                      timeoutInterval: wait))
    }

    private func download(_ request: URLRequest) async throws -> Data {
        var request = request
        request.setValue(client.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw JellyfinError.server(status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: nil)
        }
        return data
    }

    func primaryImageURL(for item: BaseItem) -> URL? { client.primaryImageURL(for: item, maxHeight: 600) }

    func reportStart(_ report: PlaybackReport) async throws { try await client.reportStart(report) }
    func reportProgress(_ report: PlaybackReport) async throws { try await client.reportProgress(report) }
    func reportStopped(_ report: PlaybackReport) async throws { try await client.reportStopped(report) }
    func endEncoding(playSessionId: String) async throws { try await client.endEncoding(playSessionId: playSessionId) }
}
