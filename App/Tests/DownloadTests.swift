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
