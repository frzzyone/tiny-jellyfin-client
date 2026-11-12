import PlayerCore
import JellyfinKit
import XCTest
@testable import TinyJellyfin

final class DownloadStoreTests: XCTestCase {
    var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("downloads-\(UUID().uuidString)")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func testRecordsRoundTripAndADamagedFolderIsSkipped() throws {
        let store = DownloadStore(root: root)
        var film = download("finch", kind: .user)
        film.item.mediaSources = [source(streams: [MediaStream(type: .video, index: 0, codec: "hevc")])]
        film.status = .failed("Not enough space")
        try store.save(film)
        try store.save(download("silo-1", kind: .forYou))
        try FileManager.default.createDirectory(at: store.folder("broken"), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: store.file("broken", "record.json"))
        store.dismissed = ["dune"]

        let again = DownloadStore(root: root)
        XCTAssertEqual(again.records().map(\.id), ["finch", "silo-1"], "oldest first, the broken folder skipped")
        XCTAssertEqual(again.record(id: "finch"), film)
        XCTAssertEqual(again.dismissed, ["dune"])
        XCTAssertEqual(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testDeleteFreesTheFolder() throws {
        let store = DownloadStore(root: root)
        try store.save(download("finch", kind: .user))
        try Data(count: 1000).write(to: store.file("finch", "media.mkv"))
        XCTAssertGreaterThan(store.bytes("finch"), 1000)
        store.delete("finch")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.folder("finch").path))
        try store.save(download("silo-1", kind: .forYou))
        store.dismissed = ["dune"]
        store.deleteAll()
        XCTAssertEqual(store.records(), [])
        XCTAssertEqual(store.dismissed, [])
    }

    /// The player is told what the phone has: a copy's one audio track and the subtitles fetched
    /// with it, as files; an original's own tracks.
    func testDownloadedSourceForACopyAndAnOriginal() {
        var video = MediaStream(type: .video, index: 0, codec: "av1")
        video.width = 3840
        video.height = 2160
        var embeddedText = MediaStream(type: .subtitle, index: 3, codec: "subrip")
        embeddedText.isTextSubtitleStream = true
        var external = MediaStream(type: .subtitle, index: 5, codec: "srt")
        external.isExternal = true
        var original = source(streams: [video, MediaStream(type: .audio, index: 1, codec: "dts"),
                                        MediaStream(type: .audio, index: 2, codec: "eac3"),
                                        embeddedText, MediaStream(type: .subtitle, index: 4, codec: "pgssub"), external])
        original.defaultAudioStreamIndex = 2
        original.defaultSubtitleStreamIndex = 4

        let copy = DownloadedSource.make(original, isCopy: true, audio: nil, subtitles: [3, 5])
        XCTAssertEqual(copy.audioStreams.map(\.index), [2], "the server's pick for the user")
        XCTAssertEqual(copy.subtitleStreams.map(\.index), [3, 5])
        XCTAssertTrue(copy.subtitleStreams.allSatisfy { $0.isExternal == true }, "files beside the copy")
        XCTAssertNil(copy.defaultSubtitleStreamIndex, "the picture track didn't come along")
        XCTAssertEqual(copy.videoStream?.height, 1080)
        XCTAssertEqual(copy.videoStream?.width, 1920)
        XCTAssertEqual(copy.container, "ts")

        let file = DownloadedSource.make(original, isCopy: false, audio: nil, subtitles: [])
        XCTAssertEqual(file.audioStreams.count, 2)
        XCTAssertEqual(file.subtitleStreams.map(\.index), [3, 4], "embedded tracks stay; the external one wasn't fetched")
        XCTAssertEqual(file.subtitleStreams.first?.isExternal, nil)
        XCTAssertEqual(file.defaultSubtitleStreamIndex, 4)
    }

    func testSizeIsTheFileWhenSmallElseTheCopysBitrate() {
        var small = BaseItem(id: "s")
        small.runTimeTicks = Ticks.from(seconds: 3600)
        var smallSource = source(streams: [MediaStream(type: .video, index: 0)])
        smallSource.size = 2_000_000_000
        smallSource.bitrate = 5_000_000
        small.mediaSources = [smallSource]
        XCTAssertEqual(DownloadSize.estimate(small), 2_000_000_000)

        var remux = small
        remux.mediaSources![0].bitrate = 60_000_000
        remux.mediaSources![0].size = 27_000_000_000
        XCTAssertEqual(DownloadSize.estimate(remux), 3_600_000_000, "8 Mbps for an hour")
    }
}

final class ProgressQueueTests: XCTestCase {
    final class FakeServer: ProgressServer {
        var data: [String: UserItemData] = [:]
        var failing: Set<String> = []
        var sent: [(String, Double, Bool, Date)] = []

        func userData(itemId: String) async throws -> UserItemData? {
            if failing.contains(itemId) { throw URLError(.notConnectedToInternet) }
            return data[itemId]
        }

        func updateUserData(_ itemId: String, positionSeconds: Double, played: Bool, lastPlayed: Date) async throws -> UserItemData {
            sent.append((itemId, positionSeconds, played, lastPlayed))
            return UserItemData(played: played)
        }
    }

    var url: URL!
    override func setUp() { url = FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID().uuidString).json") }
    override func tearDown() { try? FileManager.default.removeItem(at: url) }

    func testNinetyPercentIsWatchedAndEntriesSurviveARestart() {
        let queue = ProgressQueue(url: url)
        queue.record(itemId: "a", positionSeconds: 1200, runtimeSeconds: 3000)
        queue.record(itemId: "b", positionSeconds: 2750, runtimeSeconds: 3000)
        queue.record(itemId: "c", positionSeconds: 10, runtimeSeconds: nil, ended: true)
        let again = ProgressQueue(url: url)
        XCTAssertEqual(again.entries["a"]?.played, false)
        XCTAssertEqual(again.entries["a"]?.positionSeconds, 1200)
        XCTAssertEqual(again.entries["b"]?.played, true)
        XCTAssertEqual(again.entries["b"]?.positionSeconds, 0, "a watched title has no resume point")
        XCTAssertEqual(again.entries["c"]?.played, true)
    }

    func testFlushSendsKeepsFailuresAndYieldsToNewerViewing() async {
        let queue = ProgressQueue(url: url)
        let watched = Date(timeIntervalSince1970: 1_794_000_000)
        queue.record(itemId: "sent", positionSeconds: 600, runtimeSeconds: 3000, at: watched)
        queue.record(itemId: "elsewhere", positionSeconds: 1200, runtimeSeconds: 6000, at: watched)
        queue.record(itemId: "offline", positionSeconds: 60, runtimeSeconds: 3000, at: watched)
        let server = FakeServer()
        // Watched to 1:10 on the TV after the phone stopped at 20 minutes.
        server.data["elsewhere"] = UserItemData(playbackPositionTicks: Ticks.from(seconds: 4200), played: false,
                                                lastPlayedDate: "2026-11-07T08:30:00.0000000Z")
        server.data["sent"] = UserItemData(played: false, lastPlayedDate: "2026-11-01T08:30:00.0000000Z")
        server.failing = ["offline"]

        let settled = await queue.flush(to: server)
        XCTAssertEqual(settled, ["sent": false, "elsewhere": false])
        XCTAssertEqual(server.sent.map(\.0), ["sent"], "the newer viewing on the TV is kept")
        XCTAssertEqual(server.sent.first?.1, 600)
        XCTAssertEqual(server.sent.first?.3, watched, "stamped with when it was watched, not when it was sent")
        XCTAssertEqual(Array(queue.entries.keys), ["offline"], "kept for next time")
        XCTAssertEqual(Array(ProgressQueue(url: url).entries.keys), ["offline"])
    }

    func testJellyfinDatesWithSevenFractionDigits() {
        XCTAssertEqual(ProgressQueue.date("2026-11-10T08:30:00.0000000Z"), ProgressQueue.date("2026-11-10T08:30:00Z"))
        XCTAssertNotNil(ProgressQueue.date("2026-11-10T08:30:00Z"))
    }
}

final class DownloadPlannerTests: XCTestCase {
    func episode(_ id: String, series: String) -> BaseItem {
        var item = BaseItem(id: id, name: id, type: .episode)
        item.seriesId = series
        return item
    }

    func film(_ id: String) -> BaseItem { BaseItem(id: id, name: id, type: .movie) }

    let gb: Int64 = 1_000_000_000

    func testSmartDownloadsSwapsAFinishedEpisodeForTheNext() {
        let finished = download("silo-3", kind: .user, type: .episode)
        let next = episode("silo-4", series: "silo")
        let swap = DownloadPlanner.afterFinishing(finished, next: next, records: [finished])
        XCTAssertEqual(swap.delete, "silo-3")
        XCTAssertEqual(swap.download?.item.id, "silo-4")
        XCTAssertEqual(swap.download?.kind, .user, "the user's own, as the finished one was")

        let pick = download("silo-3", kind: .forYou, type: .episode)
        XCTAssertEqual(DownloadPlanner.afterFinishing(pick, next: next, records: [pick]).download?.kind, .forYou)

        let end = DownloadPlanner.afterFinishing(finished, next: nil, records: [finished])
        XCTAssertEqual(end.delete, "silo-3", "end of the series: deleted, nothing new")
        XCTAssertNil(end.download)

        let have = download("silo-4", kind: .user, type: .episode)
        XCTAssertNil(DownloadPlanner.afterFinishing(finished, next: next, records: [finished, have]).download,
                     "the next one is already on the phone")

        let movie = download("finch", kind: .user, type: .movie)
        let none = DownloadPlanner.afterFinishing(movie, next: nil, records: [movie])
        XCTAssertNil(none.delete, "a film stays")
        XCTAssertNil(none.download)
    }

    func testKeepsThreeShowsAndTheTopFilmInOrder() {
        let nextUp = [episode("a2", series: "a"), episode("b5", series: "b"), episode("c1", series: "c"), episode("d9", series: "d")]
        let resume = [episode("a1", series: "a"), film("finch"), film("dune")]
        let plan = DownloadPlanner.forYou(nextUp: nextUp, resume: resume, records: [], dismissed: [], busy: [],
                                          freeBytes: 100 * gb, size: { _ in 3 * self.gb })
        XCTAssertEqual(plan.download.map(\.id), ["a2", "b5", "c1", "finch"])
    }

    func testStopsAtTheBudgetWithoutSkippingAhead() {
        let nextUp = [episode("a2", series: "a"), episode("b5", series: "b"), episode("c1", series: "c")]
        let sizes: [String: Int64] = ["a2": 6 * gb, "b5": 6 * gb, "c1": 6 * gb, "finch": 2 * gb]
        let plan = DownloadPlanner.forYou(nextUp: nextUp, resume: [film("finch")], records: [], dismissed: [], busy: [],
                                          freeBytes: 100 * gb, size: { sizes[$0.id]! })
        XCTAssertEqual(plan.download.map(\.id), ["a2", "b5"], "c1 would pass 15 GB, and the small film waits behind it")
    }

    func testKeepsFiveGigabytesFree() {
        let plan = DownloadPlanner.forYou(nextUp: [episode("a2", series: "a")], resume: [], records: [], dismissed: [], busy: [],
                                          freeBytes: 6 * gb, size: { _ in 3 * self.gb })
        XCTAssertEqual(plan.download, [])
        // Space a download under way still needs counts as taken.
        var underWay = download("x", kind: .user)
        underWay.status = .downloading
        underWay.expectedBytes = 4 * gb
        let tight = DownloadPlanner.forYou(nextUp: [episode("a2", series: "a")], resume: [], records: [underWay], dismissed: [], busy: [],
                                           freeBytes: 11 * gb, size: { _ in 3 * self.gb })
        XCTAssertEqual(tight.download, [], "11 GB free, 4 GB still coming: 3 GB more would leave 4")
    }

    func testUserDownloadsCountAsReadyAndDismissedPicksStayOut() {
        let nextUp = [episode("a2", series: "a"), episode("b5", series: "b")]
        var mine = download("a2", kind: .user, type: .episode)
        mine.status = .done
        mine.receivedBytes = 14 * gb
        let plan = DownloadPlanner.forYou(nextUp: nextUp, resume: [film("finch")], records: [mine], dismissed: ["b5"], busy: [],
                                          freeBytes: 100 * gb, size: { _ in 3 * self.gb })
        XCTAssertEqual(plan.download.map(\.id), ["finch"], "a2 is the user's (not counted), b5 was deleted by hand")
        XCTAssertEqual(plan.delete, [])
        XCTAssertEqual(DownloadPlanner.stillDismissed(["b5", "gone"], nextUp: nextUp, resume: []), ["b5"],
                       "a dismissed pick that left the rows may be picked again later")
    }

    func testDeletesPicksNoLongerWantedButNotTheUsersOrBusyOnes() {
        var old = download("a1", kind: .forYou, type: .episode)
        old.status = .done
        let playing = download("b4", kind: .forYou, type: .episode)
        let mine = download("z1", kind: .user, type: .episode)
        let plan = DownloadPlanner.forYou(nextUp: [episode("a2", series: "a")], resume: [], records: [old, playing, mine],
                                          dismissed: [], busy: ["b4"], freeBytes: 100 * gb, size: { _ in self.gb })
        XCTAssertEqual(plan.delete, ["a1"])
        XCTAssertEqual(plan.download.map(\.id), ["a2"])
    }
}

func download(_ id: String, kind: DownloadRecord.Kind, type: ItemKind = .movie) -> DownloadRecord {
    DownloadRecord(item: BaseItem(id: id, name: id, type: type), kind: kind, isCopy: false, mediaFile: "media.mkv",
                   expectedBytes: 1_000_000_000)
}

func source(streams: [MediaStream]) -> MediaSourceInfo {
    var source = try! JSONDecoder().decode(MediaSourceInfo.self, from: Data("{}".utf8))
    source.id = "src"
    source.mediaStreams = streams
    return source
}

/// A download plays in the same player, answered from the phone.
@MainActor
final class LocalPlaybackTests: XCTestCase {
    final class Reports: @unchecked Sendable {
        let lock = NSLock()
        var all: [(id: String, position: Double, stopped: Bool)] = []
        func add(_ id: String, _ position: Double, _ stopped: Bool) { lock.withLock { all.append((id, position, stopped)) } }
        var stops: [Double] { lock.withLock { all.filter(\.stopped).map(\.position) } }
    }

    func testACopyPlaysFromThePhoneWithItsSubtitlesAndNoQualityMenu() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("1\n00:00:01,000 --> 00:00:04,000\nHello from the phone\n".utf8)
            .write(to: folder.appendingPathComponent(LocalPlaybackService.subtitleFile(2, picture: false)))

        var item = movie(height: 2160)
        item.mediaSources = [DownloadedSource.make(item.mediaSources![0], isCopy: true, audio: nil, subtitles: [2])]
        var download = DownloadRecord(item: item, kind: .user, isCopy: true, mediaFile: "media.ts", expectedBytes: 1)
        download.status = .done
        download.timelineOffset = -1.44
        let reports = Reports()
        let service = LocalPlaybackService(record: download, folder: folder,
                                           userData: UserItemData(playbackPositionTicks: Ticks.from(seconds: 120)),
                                           onReport: { reports.add($0, $1, $2) })

        var engines: [FakeEngine] = []
        let controller = PlaybackController(engineFactory: { let e = FakeEngine(); engines.append(e); return e },
                                            preferences: AppPreferences(defaults: UserDefaults(suiteName: "lp-\(UUID().uuidString)")!),
                                            capabilities: PlaybackCapabilities(av1: false))
        controller.start(item: item, resume: true, service: service)
        let started = await eventually { controller.session != nil }
        XCTAssertTrue(started, "\(controller.status)")
        let engine = engines.last!
        let (source, startAt) = engine.prepared[0]
        XCTAssertEqual(source.url, folder.appendingPathComponent("media.ts"))
        XCTAssertTrue(source.headers.isEmpty)
        XCTAssertEqual(source.timelineOffset, -1.44)
        XCTAssertNil(source.audioTrack, "a copy has one audio track")
        XCTAssertEqual(startAt, 120, "from where the phone knows the user stopped")
        XCTAssertEqual(controller.qualityOptions, [])
        XCTAssertEqual(controller.qualityLabel, "Downloaded")
        XCTAssertEqual(controller.subtitleOptions.map(\.id), [2])

        controller.selectSubtitle(2)
        let cues = await eventually { engine.externalCues?.first?.text == "Hello from the phone" }
        XCTAssertTrue(cues, "subtitles from the file beside the copy")

        engine.currentTime = 300
        controller.stop()
        let stopped = await eventually { reports.stops == [300] }
        XCTAssertTrue(stopped, "the stop goes to the phone's queue: \(reports.all)")
    }
}

@MainActor
final class DownloadsTests: XCTestCase {
    final class FakeTransfer: DownloadTransfer {
        var begun: [(id: String, url: URL?, resume: Data?, destination: URL)] = []
        var cancelled: [String] = []
        func begin(id: String, request: URLRequest, resumeData: Data?, destination: URL) {
            begun.append((id, request.url, resumeData, destination))
        }
        func cancel(id: String) { cancelled.append(id) }
        func cancelAll() { cancelled.append("*") }
    }

    final class FakeServer: DownloadServer, @unchecked Sendable {
        var streams: [String: ResolvedStream] = [:]
        var items: [String: BaseItem] = [:]
        var nextUpBySeries: [String: BaseItem] = [:]
        var nextUpRow: [BaseItem] = []
        var ended: [String] = []
        var userData: [String: UserItemData] = [:]
        var updates: [String] = []
        let files: URL

        init(files: URL) { self.files = files }

        func resolveDownload(_ item: BaseItem) async throws -> ResolvedStream {
            guard let stream = streams[item.id] else { throw JellyfinError.noPlayableStream(nil) }
            return stream
        }
        func item(id: String) async throws -> BaseItem {
            guard let item = items[id] else { throw JellyfinError.noPlayableStream(nil) }
            return item
        }
        func nextUp(limit: Int, seriesId: String?) async throws -> [BaseItem] {
            seriesId.map { nextUpBySeries[$0].map { [$0] } ?? [] } ?? nextUpRow
        }
        func resumeItems(limit: Int) async throws -> [BaseItem] { [] }
        func endEncoding(playSessionId: String) async throws { ended.append(playSessionId) }
        func userData(itemId: String) async throws -> UserItemData? { userData[itemId] }
        func updateUserData(_ itemId: String, positionSeconds: Double, played: Bool, lastPlayed: Date) async throws -> UserItemData {
            updates.append(itemId)
            return UserItemData(played: played)
        }
        func request(_ url: URL) -> URLRequest { URLRequest(url: url) }
        func subtitleURL(itemId: String, mediaSourceId: String, streamIndex: Int, picture: Bool) -> URL {
            files.appendingPathComponent("sub\(streamIndex).\(picture ? "sup" : "srt")")
        }
        func posterURL(for item: BaseItem) -> URL? { nil }
    }

    var root: URL!
    var transfer: FakeTransfer!
    var server: FakeServer!
    var probed: (start: Double, duration: Double?) = (0, 600)

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("dls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        transfer = FakeTransfer()
        server = FakeServer(files: root)
        try Data("1\n00:00:01,000 --> 00:00:02,000\nHi\n".utf8).write(to: root.appendingPathComponent("sub2.srt"))
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func makeDownloads(free: Int64 = 100_000_000_000) -> Downloads {
        let downloads = Downloads(store: DownloadStore(root: root.appendingPathComponent("store")), server: { [server] in server },
                                  probe: { [unowned self] _ in self.probed })
        downloads.transfer = transfer
        downloads.freeBytes = { free }
        return downloads
    }

    func film(_ id: String, bitrate: Int = 20_000_000) -> BaseItem {
        var item = movie()
        item.id = id
        item.mediaSources![0].size = 3_000_000_000
        item.mediaSources![0].bitrate = bitrate
        item.mediaSources![0].container = "mkv"
        return item
    }

    func stream(_ item: BaseItem, copy: Bool, session: String? = nil) -> ResolvedStream {
        ResolvedStream(url: URL(string: "https://jf.test/\(item.id)/\(copy ? "stream.ts" : "stream")")!,
                       playMethod: copy ? .transcode : .directPlay, mediaSource: item.mediaSources![0],
                       mediaSourceId: "src", playSessionId: session, timelineOffset: 0)
    }

    /// Writes the file the transfer would have saved, then reports it finished.
    func finish(_ downloads: Downloads, _ id: String) async throws {
        let destination = transfer.begun.last { $0.id == id }!.destination
        try Data(count: 4096).write(to: destination)
        await downloads.finished(id)
    }

    func testAnOriginalDownloadsAsItIsWithItsExternalSubtitles() async throws {
        let item = film("small", bitrate: 5_000_000)
        server.items["small"] = item
        server.streams["small"] = stream(item, copy: false)
        let downloads = makeDownloads()
        await downloads.download(item)
        let record = try XCTUnwrap(downloads.record("small"))
        XCTAssertFalse(record.isCopy)
        XCTAssertEqual(record.mediaFile, "media.mkv")
        XCTAssertEqual(record.status, .downloading)
        XCTAssertEqual(record.expectedBytes, 3_000_000_000, "the file's own size")
        XCTAssertEqual(transfer.begun.map(\.url?.path), ["/small/stream"])
        XCTAssertEqual(record.source?.subtitleStreams.map(\.index), [2, 3], "embedded tracks stay; external 4's file never came")
        try await finish(downloads, "small")
        XCTAssertEqual(downloads.record("small")?.status, .done)
        XCTAssertEqual(downloads.fraction(downloads.record("small")!), 1)
        XCTAssertNotNil(downloads.playbackService(for: item))
    }

    func testACopyStoresItsStartAndEndsItsEncode() async throws {
        let item = film("remux")
        server.streams["remux"] = stream(item, copy: true, session: "ps1")
        let downloads = makeDownloads()
        await downloads.download(item)
        XCTAssertEqual(downloads.record("remux")?.mediaFile, "media.ts")
        XCTAssertEqual(downloads.record("remux")?.source?.audioStreams.map(\.index), [1], "one audio track")
        XCTAssertEqual(downloads.record("remux")?.source?.subtitleStreams.map(\.index), [2], "the text track whose file came")
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloads.store.file("remux", "sub-2.srt").path))
        probed = (1.44, 600)
        try await finish(downloads, "remux")
        XCTAssertEqual(downloads.record("remux")?.status, .done)
        XCTAssertEqual(downloads.record("remux")?.timelineOffset, -1.44)
        let ended = await eventually { self.server.ended == ["ps1"] }
        XCTAssertTrue(ended, "the server stops encoding: \(server.ended)")
    }

    func testATruncatedCopyIsMadeAgainThenFails() async throws {
        let item = film("remux")
        server.streams["remux"] = stream(item, copy: true, session: "ps1")
        let downloads = makeDownloads()
        await downloads.download(item)
        probed = (1.44, 300)
        try await finish(downloads, "remux")
        XCTAssertEqual(transfer.begun.count, 2, "a second copy")
        try await finish(downloads, "remux")
        try await finish(downloads, "remux")
        XCTAssertEqual(transfer.begun.count, 3)
        XCTAssertEqual(downloads.record("remux")?.status, .failed("The server stopped making the copy"))
        await downloads.tryAgain("remux")
        XCTAssertEqual(transfer.begun.count, 4)
    }

    func testOneCopyAtATimeAndOriginalsAlongside() async throws {
        let a = film("a"), b = film("b"), small = film("small", bitrate: 4_000_000)
        server.streams = ["a": stream(a, copy: true), "b": stream(b, copy: true), "small": stream(small, copy: false)]
        let downloads = makeDownloads()
        await downloads.download(a)
        await downloads.download(b)
        await downloads.download(small)
        XCTAssertEqual(transfer.begun.map(\.id), ["a", "small"])
        XCTAssertEqual(downloads.record("b")?.status, .queued)
        try await finish(downloads, "a")
        XCTAssertEqual(transfer.begun.map(\.id), ["a", "small", "b"])
    }

    func testAnInterruptedOriginalResumes() async throws {
        let item = film("small", bitrate: 5_000_000)
        server.streams["small"] = stream(item, copy: false)
        let downloads = makeDownloads()
        await downloads.download(item)
        await downloads.failed("small", error: URLError(.networkConnectionLost), resumeData: Data("resume".utf8))
        XCTAssertEqual(transfer.begun.last?.resume, Data("resume".utf8))
        XCTAssertEqual(downloads.record("small")?.status, .downloading)
    }

    func testNotEnoughSpace() async {
        let item = film("remux")
        server.streams["remux"] = stream(item, copy: true)
        let downloads = makeDownloads(free: 1_000_000_000)
        await downloads.download(item)
        XCTAssertEqual(downloads.record("remux")?.status, .failed("Not enough space on this iPhone"))
        XCTAssertEqual(transfer.begun.count, 0)
    }

    func testDeletingAPickDismissesItAndStopsTheTransfer() async {
        let item = film("remux")
        server.streams["remux"] = stream(item, copy: true, session: "ps9")
        let downloads = makeDownloads()
        await downloads.download(item, kind: .forYou)
        downloads.delete("remux")
        XCTAssertNil(downloads.record("remux"))
        XCTAssertEqual(transfer.cancelled, ["remux"])
        XCTAssertEqual(downloads.store.dismissed, ["remux"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloads.store.folder("remux").path))
    }

    func testFinishingAnEpisodeSwapsItForTheNextAfterTheSync() async throws {
        var e3 = film("e3", bitrate: 4_000_000)
        e3.type = .episode
        e3.seriesId = "silo"
        var e4 = e3
        e4.id = "e4"
        server.streams = ["e3": stream(e3, copy: false), "e4": stream(e4, copy: false)]
        server.items = ["e3": e3, "e4": e4]
        server.nextUpBySeries["silo"] = e4
        let downloads = makeDownloads()
        await downloads.download(e3)
        try await finish(downloads, "e3")
        downloads.played("e3", position: 595, stopped: false)
        await downloads.sync()
        XCTAssertEqual(server.updates, ["e3"], "watched, sent")
        XCTAssertNil(downloads.record("e3"), "deleted once the server knows")
        XCTAssertEqual(downloads.record("e4")?.kind, .user)
        XCTAssertEqual(downloads.record("e4")?.status, .downloading)
    }
}
