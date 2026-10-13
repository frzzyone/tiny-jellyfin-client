import JellyfinKit
import PlayerCore
import XCTest
@testable import TinyJellyfin

@MainActor
final class PlaybackControllerTests: XCTestCase {
    var engines: [FakeEngine] = []
    var prefs: AppPreferences!

    override func setUp() async throws {
        engines = []
        prefs = AppPreferences(defaults: UserDefaults(suiteName: "pc-\(UUID().uuidString)")!)
    }

    func makeController() -> PlaybackController {
        let controller = PlaybackController(engineFactory: { [unowned self] in
            let engine = FakeEngine()
            self.engines.append(engine)
            return engine
        }, preferences: prefs, capabilities: PlaybackCapabilities(av1: false))
        controller.progressInterval = 0.2
        return controller
    }

    func started(_ item: BaseItem = movie(), resume: Bool = false, method: PlayMethod = .directPlay)
        async -> (PlaybackController, FakeService, FakeEngine) {
        let controller = makeController()
        let service = FakeService(item: item)
        service.nextMethod = method
        controller.start(item: item, resume: resume, service: service)
        let ok = await eventually { controller.session != nil }
        XCTAssertTrue(ok, "playback did not start: \(controller.status)")
        return (controller, service, engines.last!)
    }

    func testPictureBarsComeFromTwoAgreeingLooksAndOnlyNarrow() async {
        let (controller, _, engine) = await started()
        engine.send(.state(.playing))
        controller.barSampleInterval = 0.05
        engine.displayedFrame = letterboxedFrame(width: 320, height: 200, top: 50, bottom: 50)
        let dark = await eventually(1) { controller.pictureBars != nil }
        XCTAssertTrue(dark)
        XCTAssertEqual(controller.pictureBars, PictureBars(top: 0.25, bottom: 0.25))
        engine.displayedFrame = letterboxedFrame(width: 320, height: 200, top: 25, bottom: 30)
        let narrowed = await eventually(1) { controller.pictureBars == PictureBars(top: 0.125, bottom: 0.15) }
        XCTAssertTrue(narrowed, "\(String(describing: controller.pictureBars))")
        engine.displayedFrame = letterboxedFrame(width: 320, height: 200, top: 90, bottom: 90)
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(controller.pictureBars, PictureBars(top: 0.125, bottom: 0.15), "a darker frame never widens the bars")
        controller.stop()
        XCTAssertNil(controller.pictureBars)
    }

    func testCycleSubtitleSkipsImageTracksAndEndsOff() async {
        let (controller, _, _) = await started()
        var seen: [Int?] = []
        for _ in 0..<4 {
            controller.cycleSubtitle()
            seen.append(controller.selectedSubtitle)
        }
        XCTAssertEqual(seen, [2, 4, nil, 2], "English, French (external), Off, English; never the PGS track")
        controller.stop()
    }

    func testDigitKeysJumpByTenths() async {
        let (controller, _, engine) = await started()
        controller.jump(toTenth: 5)
        let jumped = await eventually { engine.seeks.last == 300 }
        XCTAssertTrue(jumped, "\(engine.seeks)")
        controller.stop()
    }

    /// The Apple TV switches the display mode here; the clock must not run until it is done.
    func testBeforePlayRunsBetweenOpenAndPlay() async {
        let controller = makeController()
        var seen: (prepared: Int, playing: Bool)?
        controller.beforePlay = { engine in
            let fake = engine as! FakeEngine
            seen = (fake.prepared.count, fake.isPlaying)
            try? await Task.sleep(for: .milliseconds(50))
        }
        controller.start(item: movie(), resume: false, service: FakeService(item: movie()))
        let ok = await eventually { controller.session != nil && self.engines.last?.isPlaying == true }
        XCTAssertTrue(ok)
        XCTAssertEqual(seen?.prepared, 1)
        XCTAssertEqual(seen?.playing, false)
    }

    func testVideoSizeArrivesAfterOpenForTranscodes() async {
        let controller = makeController()
        let service = FakeService(item: movie())
        let sizeLater = FakeEngine()
        sizeLater.videoSize = nil
        engines.append(sizeLater)
        let transcoding = PlaybackController(engineFactory: { sizeLater }, preferences: prefs,
                                             capabilities: PlaybackCapabilities(av1: false))
        _ = controller
        transcoding.start(item: movie(), resume: false, service: service)
        let started = await eventually { transcoding.session != nil }
        XCTAssertTrue(started)
        XCTAssertNil(transcoding.videoSize)
        sizeLater.videoSize = CGSize(width: 1280, height: 720)
        let known = await eventually { transcoding.videoSize == CGSize(width: 1280, height: 720) }
        XCTAssertTrue(known, "the controller picks the size up once the engine knows it")
        transcoding.stop()
    }

    func testPictureBarsStopBeingMeasuredOnceSettled() async {
        let (controller, _, engine) = await started()
        engine.send(.state(.playing))
        controller.barSampleInterval = 0.02
        controller.barSettledLooks = 5
        engine.displayedFrame = letterboxedFrame(width: 320, height: 200, top: 50, bottom: 50)
        let settled = await eventually(3) { controller.barsSettled }
        XCTAssertTrue(settled)
        XCTAssertEqual(controller.pictureBars, PictureBars(top: 0.25, bottom: 0.25))
        engine.displayedFrame = letterboxedFrame(width: 320, height: 200, top: 10, bottom: 10)
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(controller.pictureBars, PictureBars(top: 0.25, bottom: 0.25), "no longer looking at the frames")
    }

    func testResumeUsesTheServersPositionNotTheCards() async {
        let controller = makeController()
        let service = FakeService(item: movie(resumeAt: 500))   // what the server says now
        controller.start(item: movie(resumeAt: 100), resume: true, service: service) // a stale card
        let ok = await eventually { controller.session != nil }
        XCTAssertTrue(ok)
        XCTAssertEqual(engines.last?.prepared.first?.1, 500)
        XCTAssertEqual(controller.currentTime, 500)
        controller.stop()
        let fresh = FakeService(item: movie())   // watched to the end: no position any more
        controller.start(item: movie(resumeAt: 100), resume: true, service: fresh)
        let again = await eventually { controller.session != nil }
        XCTAssertTrue(again)
        XCTAssertEqual(engines.last?.prepared.first?.1, 0, "the server's answer wins even when it is 'start over'")
    }

    func testStartPlaysFromBeginningAndReports() async {
        let (controller, service, engine) = await started()
        XCTAssertEqual(engine.prepared.first?.1, 0)
        XCTAssertEqual(engine.prepared.first?.0.headers["Authorization"], "MediaBrowser Token=\"t\"")
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(controller.qualityLabel, "Original · Direct Play")
        let reported = await eventually { service.recorded.contains("start:ps1") }
        XCTAssertTrue(reported)
    }

    func testResumeStartsAtSavedPosition() async {
        let (_, service, engine) = await started(movie(resumeAt: 2530), resume: true)
        XCTAssertEqual(engine.prepared.first?.1, 2530)
        XCTAssertEqual(service.resolveCalls.first?.start, 2530)
    }

    func testPeriodicAndEventProgressReports() async {
        let (controller, service, _) = await started()
        let periodic = await eventually { service.recorded.contains("progress:ps1:playing") }
        XCTAssertTrue(periodic)
        controller.pause()
        let paused = await eventually { service.recorded.contains("progress:ps1:paused") }
        XCTAssertTrue(paused)
    }

    func testStopReportsOnceAndEndsTranscode() async {
        let (controller, service, engine) = await started(method: .transcode)
        engine.currentTime = 61
        controller.stop()
        controller.stop()
        let done = await eventually { service.recorded.contains("endEncoding:ps1") }
        XCTAssertTrue(done)
        XCTAssertEqual(service.recorded.filter { $0.hasPrefix("stopped:") }, ["stopped:ps1:61"])
        XCTAssertTrue(engine.stopped)
    }

    func testDirectPlayStopDoesNotDeleteEncodings() async {
        let (controller, service, _) = await started(method: .directPlay)
        controller.stop()
        _ = await eventually { service.recorded.contains { $0.hasPrefix("stopped:") } }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(service.recorded.contains { $0.hasPrefix("endEncoding") })
    }

    func testEndedReportsStopAtEnd() async {
        let (controller, service, engine) = await started()
        engine.currentTime = 600
        engine.send(.state(.ended))
        XCTAssertEqual(controller.status, .ended)
        _ = await eventually { service.recorded.contains("stopped:ps1:600") }
        controller.stop()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(service.recorded.filter { $0.hasPrefix("stopped:") }.count, 1, "single stop")
    }

    func testFailureThenRetryResumesFromLastPosition() async {
        let (controller, service, engine) = await started()
        engine.currentTime = 930
        engine.send(.state(.failed("network lost")))
        XCTAssertEqual(controller.status, .failed("network lost"))
        _ = await eventually { service.recorded.contains("stopped:ps1:930") }
        controller.retry()
        let retried = await eventually { self.engines.count == 2 && controller.session != nil }
        XCTAssertTrue(retried)
        XCTAssertEqual(engines[1].prepared.first?.1 ?? 0, 930, accuracy: 0.5)
    }

    func testNoPlayableStream() async {
        let controller = makeController()
        let service = FakeService(item: movie())
        service.resolveError = JellyfinError.noPlayableStream(nil)
        controller.start(item: movie(), resume: false, service: service)
        let failed = await eventually { if case .failed = controller.status { return true }; return false }
        XCTAssertTrue(failed)
        XCTAssertTrue(engines.isEmpty, "no empty player is opened")
    }

    // MARK: Quality

    func testDefaultQualityFromPreferences() async {
        prefs.setPreferredQualityId("720p-4", server: URL(string: "https://jf.test")!)
        let (controller, service, _) = await started()
        XCTAssertEqual(service.resolveCalls.first?.quality.label, "720p 4 Mbps")
        XCTAssertEqual(controller.qualityLabel, "720p 4 Mbps · Transcode")
    }

    func testHiddenRememberedPresetStartsAtOriginal() async {
        prefs.setPreferredQualityId("2160p-40", server: URL(string: "https://jf.test")!)
        let (controller, _, _) = await started(movie(height: 1080))
        XCTAssertEqual(controller.session?.quality, .original)
        XCTAssertFalse(controller.qualityOptions.contains { $0.id == "2160p-40" })
        XCTAssertEqual(prefs.preferredQualityId(server: URL(string: "https://jf.test")!), "2160p-40")
    }

    func testSwitchQualityKeepsPositionAndRetiresOldSession() async {
        let (controller, service, engine) = await started(method: .transcode)
        engine.currentTime = 3750
        controller.selectQuality(QualityPreset.with(id: "480p-1.5")!)
        XCTAssertTrue(controller.isSwitching)
        let switched = await eventually { controller.session?.quality.id == "480p-1.5" && !controller.isSwitching }
        XCTAssertTrue(switched)
        XCTAssertEqual(engine.switches.first?.1 ?? 0, 3752, accuracy: 0.01)
        XCTAssertEqual(engines.count, 1, "the same engine splices; no new player")
        let retired = await eventually {
            service.recorded.contains("stopped:ps1:3750") && service.recorded.contains("endEncoding:ps1")
                && service.recorded.contains("start:ps2")
        }
        XCTAssertTrue(retired, "\(service.recorded)")
        XCTAssertEqual(prefs.preferredQualityId(server: service.serverURL), "480p-1.5")
        XCTAssertEqual(controller.qualityLabel, "480p 1.5 Mbps · Transcode")
    }

    func testSelectingCurrentQualityIsANoOp() async {
        let (controller, _, engine) = await started()
        controller.selectQuality(.original)
        XCTAssertFalse(controller.isSwitching)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(engine.switches.isEmpty)
    }

    func testFailedSwitchKeepsPreviousQuality() async {
        let (controller, service, engine) = await started()
        engine.switchError = EngineError("boom")
        controller.selectQuality(QualityPreset.with(id: "720p-4")!)
        let failed = await eventually { controller.switchError != nil }
        XCTAssertTrue(failed)
        XCTAssertEqual(controller.session?.quality, .original)
        XCTAssertEqual(controller.session?.playSessionId, "ps1")
        XCTAssertFalse(controller.isSwitching)
        XCTAssertNil(prefs.preferredQualityId(server: service.serverURL))
    }

    func testFailedSwitchStopsItsTranscode() async {
        let (controller, service, engine) = await started(method: .transcode)
        engine.switchError = EngineError("boom")
        controller.selectQuality(QualityPreset.with(id: "720p-4")!)
        let stopped = await eventually { service.recorded.contains("endEncoding:ps2") }
        XCTAssertTrue(stopped, "the server stops the stream the switch asked for: \(service.recorded)")
        XCTAssertFalse(service.recorded.contains("endEncoding:ps1"), "the playing stream keeps going")
    }

    func testNewSelectionCancelsInFlightSwitch() async {
        let (controller, _, engine) = await started()
        engine.switchDelay = 0.3
        controller.selectQuality(QualityPreset.with(id: "1080p-20")!)
        try? await Task.sleep(nanoseconds: 50_000_000)
        controller.selectQuality(QualityPreset.with(id: "480p-1.5")!)
        let done = await eventually { controller.session?.quality.id == "480p-1.5" && !controller.isSwitching }
        XCTAssertTrue(done)
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(controller.session?.quality.id, "480p-1.5", "the cancelled switch never lands")
    }

    func testSwitchTimesOut() async {
        let (controller, _, engine) = await started()
        controller.switchTimeout = 0.2
        engine.switchDelay = 5
        controller.selectQuality(QualityPreset.with(id: "720p-4")!)
        let failed = await eventually(2) { controller.switchError != nil }
        XCTAssertTrue(failed)
        XCTAssertEqual(controller.session?.quality, .original)
    }

    func testSwitchWhilePausedStaysPaused() async {
        let (controller, _, engine) = await started()
        controller.pause()
        controller.selectQuality(QualityPreset.with(id: "720p-4")!)
        _ = await eventually { controller.session?.quality.id == "720p-4" }
        XCTAssertFalse(engine.isPlaying)
    }

    // MARK: Subtitles

    func testDefaultSubtitleFromServerUsesEmbeddedTrackInDirectPlay() async {
        let (controller, _, engine) = await started(movie(defaultSubtitle: 2))
        XCTAssertEqual(controller.selectedSubtitle, 2)
        XCTAssertEqual(engine.embeddedSubtitle, 2)
        XCTAssertNil(engine.externalCues)
    }

    func testExternalSubtitleIsDownloaded() async {
        let (controller, service, engine) = await started()
        controller.selectSubtitle(4)
        let loaded = await eventually { engine.externalCues?.first?.text == "Server cue" }
        XCTAssertTrue(loaded)
        XCTAssertTrue(service.recorded.contains("subtitle:4"))
        controller.selectSubtitle(nil)
        XCTAssertNil(engine.externalCues)
        XCTAssertNil(engine.embeddedSubtitle)
    }

    func testTranscodedPlaybackFetchesTextSubtitlesFromServer() async {
        let (controller, service, engine) = await started(method: .transcode)
        controller.selectSubtitle(2)
        let loaded = await eventually { engine.externalCues != nil }
        XCTAssertTrue(loaded)
        XCTAssertTrue(service.recorded.contains("subtitle:2"))
    }

    func testImageSubtitleIsBurnedInAndRemovedAgain() async {
        let (controller, service, engine) = await started()
        engine.currentTime = 1200
        controller.selectSubtitle(3)
        let burned = await eventually { controller.session?.burnInSubtitle == 3 }
        XCTAssertTrue(burned)
        XCTAssertEqual(service.resolveCalls.last?.subtitle, 3)
        XCTAssertEqual(engine.switches.last?.1 ?? 0, 1202, accuracy: 0.01)
        XCTAssertEqual(controller.session?.playMethod, .transcode)
        XCTAssertNil(prefs.preferredQualityId(server: service.serverURL), "burn-in is not a quality preference")

        controller.selectSubtitle(nil)
        let removed = await eventually { controller.session?.burnInSubtitle == nil && !controller.isSwitching }
        XCTAssertTrue(removed)
        XCTAssertNil(service.resolveCalls.last?.subtitle)
        XCTAssertEqual(controller.session?.playMethod, .directPlay)
    }

    func testSubtitleSurvivesQualitySwitch() async {
        let (controller, _, engine) = await started(movie(defaultSubtitle: 2))
        controller.selectQuality(QualityPreset.with(id: "720p-4")!)
        _ = await eventually { controller.session?.quality.id == "720p-4" }
        XCTAssertEqual(controller.selectedSubtitle, 2)
        // After switching to a transcode, cues come from the server.
        let loaded = await eventually { engine.externalCues != nil }
        XCTAssertTrue(loaded)
    }
}
