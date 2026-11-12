import Foundation
import JellyfinKit

/// One title on the phone: the item (its media source as downloaded), where its transfer is, and
/// whose it is.
struct DownloadRecord: Codable, Equatable, Identifiable, Sendable {
    /// Downloaded by the user, or picked by Downloads for you (which also removes it again).
    enum Kind: String, Codable, Sendable { case user, forYou }

    enum Status: Codable, Equatable, Sendable {
        case queued, downloading, done
        case failed(String)
    }

    var item: BaseItem
    var kind: Kind
    var status: Status = .queued
    /// A copy the server encodes while sending (it restarts when interrupted), not the original file.
    var isCopy: Bool
    /// The media file's name in the folder.
    var mediaFile: String
    var expectedBytes: Int64
    var receivedBytes: Int64 = 0
    var playSessionId: String?
    /// Added to the file's timestamps: a server copy starts at 1.44 s, not 0.
    var timelineOffset: Double = 0
    var attempts = 0
    var added = Date()

    var id: String { item.id }
    var source: MediaSourceInfo? { item.mediaSources?.first }
    var isDone: Bool { status == .done }
}

/// Downloads on disk: a folder per item under Application Support (kept out of backups), each with
/// `record.json`, the media file, the poster and the subtitle files. A damaged folder costs only
/// its own download.
final class DownloadStore {
    let root: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
    }

    init(root: URL = DownloadStore.defaultRoot) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = root
        try? url.setResourceValues(values)
    }

    func folder(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    func file(_ id: String, _ name: String) -> URL { folder(id).appendingPathComponent(name) }

    /// Every readable download, oldest first.
    func records() -> [DownloadRecord] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return entries.filter(\.hasDirectoryPath).compactMap { record(id: $0.lastPathComponent) }
            .sorted { $0.added < $1.added }
    }

    func record(id: String) -> DownloadRecord? {
        guard let data = try? Data(contentsOf: file(id, "record.json")) else { return nil }
        return try? decoder.decode(DownloadRecord.self, from: data)
    }

    func save(_ record: DownloadRecord) throws {
        try FileManager.default.createDirectory(at: folder(record.id), withIntermediateDirectories: true)
        try encoder.encode(record).write(to: file(record.id, "record.json"), options: .atomic)
    }

    func delete(_ id: String) { try? FileManager.default.removeItem(at: folder(id)) }

    /// Everything: downloads, the dismissed picks and the progress waiting to be sent.
    func deleteAll() {
        for entry in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    /// Bytes on disk for a download.
    func bytes(_ id: String) -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder(id), includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// Picks of Downloads for you the user deleted, not to be picked again.
    var dismissed: Set<String> {
        get { (try? decoder.decode(Set<String>.self, from: Data(contentsOf: root.appendingPathComponent("dismissed.json")))) ?? [] }
        set { try? encoder.encode(newValue).write(to: root.appendingPathComponent("dismissed.json"), options: .atomic) }
    }
}

/// The media source as the phone has it, which is what the player is told it plays.
enum DownloadedSource {
    /// A server copy keeps the one audio track it was made with, and only the subtitles fetched
    /// with it (as files beside it). An original keeps its own tracks, and its external subtitles
    /// only when they were fetched.
    static func make(_ source: MediaSourceInfo, isCopy: Bool, audio: Int?, subtitles: Set<Int>) -> MediaSourceInfo {
        var result = source
        let keptAudio = audio ?? source.defaultAudioStreamIndex ?? source.audioStreams.first?.index
        result.mediaStreams = source.mediaStreams?.compactMap { stream in
            var stream = stream
            switch stream.type {
            case .audio where isCopy:
                return stream.index == keptAudio ? stream : nil
            case .subtitle:
                if !isCopy && stream.isExternal != true { return stream }
                guard subtitles.contains(stream.index) else { return nil }
                stream.isExternal = true
                return stream
            case .video where isCopy:
                // Scaled to the copy's 1080 lines, so the facts don't promise 4K.
                if let height = stream.height, let width = stream.width, height > 1080 {
                    stream.width = width * 1080 / height
                    stream.height = 1080
                }
                return stream
            default:
                return stream
            }
        }
        if isCopy {
            result.container = "ts"
            result.defaultAudioStreamIndex = keptAudio
        }
        if let index = result.defaultSubtitleStreamIndex, !result.subtitleStreams.contains(where: { $0.index == index }) {
            result.defaultSubtitleStreamIndex = nil
        }
        result.transcodingUrl = nil
        return result
    }
}

enum DownloadSize {
    /// Bytes a download of `item` should take: the file itself when it is already within the
    /// download quality, otherwise the copy's.
    static func estimate(_ item: BaseItem) -> Int64? {
        isOriginal(item) ? item.mediaSources?.first?.size : (copy(item) ?? item.mediaSources?.first?.size)
    }

    /// Whether the file is already within the download quality, so the server will likely offer it
    /// as it is. The server has the last word when the download begins.
    static func isOriginal(_ item: BaseItem) -> Bool {
        guard let source = item.mediaSources?.first, source.size != nil, let bitrate = source.bitrate else { return false }
        return bitrate <= QualityPreset.download.maxStreamingBitrate
            && (source.videoStream?.height ?? 0) <= (QualityPreset.download.maxHeight ?? 0) + 8
    }

    /// A server copy: its bitrate over the runtime, an upper bound (copies come out near 70% of it).
    static func copy(_ item: BaseItem) -> Int64? {
        let seconds = Ticks.seconds(item.runTimeTicks ?? item.mediaSources?.first?.runTimeTicks ?? 0)
        guard seconds > 0 else { return nil }
        return Int64(Double(QualityPreset.download.maxStreamingBitrate) * seconds / 8)
    }
}
