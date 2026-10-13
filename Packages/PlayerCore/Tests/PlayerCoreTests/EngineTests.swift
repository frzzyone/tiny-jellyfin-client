#if canImport(AVFoundation)
import AVFoundation
import CoreMedia
import XCTest
@testable import PlayerCore

/// Headless engine tests: renderers run without a window; the synchronizer clock and renderer
/// status tell us whether playback works.
final class EngineTests: XCTestCase {
    override class func setUp() { FFmpegLog.configure() }

    func engine() -> FFmpegEngine {
        let engine = FFmpegEngine()
        engine.isMuted = true
        return engine
    }

    func waitFor(_ timeout: TimeInterval, _ condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    func assertPlays(_ url: URL, headers: [String: String] = [:], file: StaticString = #filePath, line: UInt = #line) async throws {
        let engine = engine()
        defer { engine.stop() }
        try await engine.prepare(source: MediaSource(url: url, headers: headers), startAt: 0)
        XCTAssertEqual(engine.state, .paused, file: file, line: line)
        engine.play()
        // Fixtures are 6 s long: require 5 s of rendered playback.
        let advanced = await waitFor(10) { engine.currentTime >= 5.0 || engine.state == .ended }
        XCTAssertTrue(advanced, "stalled: \(engine.debugSummary)", file: file, line: line)
        XCTAssertNotEqual(engine.videoRenderer.status, .failed,
                          "video renderer: \(String(describing: engine.videoRenderer.error))", file: file, line: line)
        // On iOS there is no passthrough: compressed AC-3/E-AC-3 must be accepted by the system decoder.
        XCTAssertNotEqual(engine.audioRenderer.status, .failed,
                          "audio renderer: \(String(describing: engine.audioRenderer.error))", file: file, line: line)
        if case .failed(let message) = engine.state { XCTFail(message, file: file, line: line) }
    }

    func testPlaysH264AAC() async throws { try await assertPlays(try Fixtures.url("h264_aac.mp4")) }
    func testPlaysHEVC10EAC3() async throws { try await assertPlays(try Fixtures.url("hevc10_eac3.mkv")) }
    func testPlaysDTS() async throws { try await assertPlays(try Fixtures.url("h264_dts.mkv")) }
    func testPlaysTrueHD() async throws { try await assertPlays(try Fixtures.url("h264_truehd.mkv")) }
    func testPlaysAnnexBTransportStream() async throws { try await assertPlays(try Fixtures.url("annexb.ts")) }
    func testPlaysHDR10() async throws { try await assertPlays(try Fixtures.url("hdr10.mkv")) }

    func testPlaysOverHTTPAndHLS() async throws {
        let server = try TestHTTPServer()
        try await assertPlays(server.url("hevc10_eac3.mkv"), headers: TestHTTPServer.authHeaders)
        try await assertPlays(server.url("hls/main.m3u8"), headers: TestHTTPServer.authHeaders)
    }

    func testResumeStartsAtPosition() async throws {
        let engine = engine()
        defer { engine.stop() }
        try await engine.prepare(source: MediaSource(url: try Fixtures.url("hevc10_eac3.mkv")), startAt: 3.5)
        XCTAssertEqual(engine.currentTime, 3.5, accuracy: 0.05)
        engine.play()
        let advanced = await waitFor(4) { engine.currentTime > 4.0 }
        XCTAssertTrue(advanced)
    }

    /// Once playback has settled, the video renderer must stay locked to the shared clock and the
    /// clock must advance at real time. A drift that grows over the run is the failure that pulls
    /// audio and video apart over a long movie; a constant offset at startup is not (the renderers'
    /// timebases latch a few tens of milliseconds apart when the rate is first set).
    func testClocksStayInSync() async throws {
        let engine = engine()
        defer { engine.stop() }
        try await engine.prepare(source: MediaSource(url: try Fixtures.url("h264_aac.mp4")), startAt: 0)
        engine.play()
        let started = await waitFor(3) { engine.state == .playing }
        XCTAssertTrue(started, "never started: \(engine.debugSummary)")
        try await Task.sleep(nanoseconds: 700_000_000)   // let the start transient settle

        var drifts: [Double] = []
        let firstClock = engine.synchronizer.currentTime().seconds
        let firstHost = Date()
        for _ in 0..<30 {
            let clock = engine.synchronizer.currentTime().seconds
            if let timebase = engine.videoRenderer.timebase as CMTimebase? {
                drifts.append(abs(CMTimebaseGetTime(timebase).seconds - clock))
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let elapsedClock = engine.synchronizer.currentTime().seconds - firstClock
        let elapsedHost = Date().timeIntervalSince(firstHost)

        XCTAssertFalse(drifts.isEmpty, "no video timebase: \(engine.debugSummary)")
        let worst = drifts.max() ?? 0
        XCTAssertLessThan(worst, 0.04, "video renderer drifted \(worst) s from the shared clock")
        // No progressive drift: the second half must be no worse than the first plus a margin.
        let half = drifts.count / 2
        let early = drifts[..<half].max() ?? 0, late = drifts[half...].max() ?? 0
        XCTAssertLessThan(late, early + 0.02, "drift grew over the run (\(early) s → \(late) s)")
        // The clock tracks real time, so audio is not resampling the timeline underneath us.
        XCTAssertEqual(elapsedClock, elapsedHost, accuracy: max(0.1, elapsedHost * 0.05),
                       "clock advanced \(elapsedClock) s in \(elapsedHost) s of real time")
    }

    func testSeekAccuracy() async throws {
        let server = try TestHTTPServer()
        for url in [try Fixtures.url("hevc10_eac3.mkv"), server.url("hls/main.m3u8")] {
            let engine = engine()
            try await engine.prepare(source: MediaSource(url: url, headers: TestHTTPServer.authHeaders), startAt: 0)
            var generator = SystemRandomNumberGenerator()
            for _ in 0..<10 {
                let target = Double.random(in: 0.2...5.0, using: &generator)
                await engine.seek(to: target)
                XCTAssertEqual(engine.currentTime, target, accuracy: 0.1,
                               "\(url.lastPathComponent) → \(target): \(engine.debugSummary)")
                XCTAssertEqual(engine.state, .paused, "\(url.lastPathComponent): \(engine.debugSummary)")
            }
            // Playback continues after seeking.
            await engine.seek(to: 1.0)
            engine.play()
            let advanced = await waitFor(4) { engine.currentTime > 1.8 }
            XCTAssertTrue(advanced, "\(url.lastPathComponent) did not play after seeking: \(engine.debugSummary)")
            engine.stop()
        }
    }

    func testPlaysToEndAndReportsEnded() async throws {
        let engine = engine()
        defer { engine.stop() }
        try await engine.prepare(source: MediaSource(url: try Fixtures.url("h264_aac.mp4")), startAt: 4.5)
        engine.play()
        let ended = await waitFor(6) { engine.state == .ended }
        XCTAssertTrue(ended, "not ended: \(engine.debugSummary)")
    }

    func testCorruptSectionIsSkipped() async throws {
        let engine = engine()
        defer { engine.stop() }
        try await engine.prepare(source: MediaSource(url: try Fixtures.url("corrupt.mkv")), startAt: 2)
        engine.play()
        let pastDamage = await waitFor(8) { engine.currentTime > 4.0 || engine.state == .ended }
        XCTAssertTrue(pastDamage, "stuck: \(engine.debugSummary)")
        if case .failed(let message) = engine.state { XCTFail("corrupt data should not fail playback: \(message)") }
    }

    func testTruncatedFileEndsWithoutFailing() async throws {
        let engine = engine()
        defer { engine.stop() }
        try await engine.prepare(source: MediaSource(url: try Fixtures.url("truncated.mkv")), startAt: 1.5)
        engine.play()
        let finished = await waitFor(8) {
            if case .ended = engine.state { return true }
            if case .failed = engine.state { return true }
            return false
        }
        XCTAssertTrue(finished)
        XCTAssertEqual(engine.state, .ended)
    }

    func testLostConnectionFails() async throws {
        let server = try TestHTTPServer()
        let engine = engine()
        defer { engine.stop() }
        do {
            try await engine.prepare(source: MediaSource(url: server.url("missing.mkv"), headers: TestHTTPServer.authHeaders),
                                     startAt: 0)
            XCTFail("expected failure")
        } catch {
            if case .failed = engine.state {} else { XCTFail("state \(engine.state)") }
        }
    }

    func testStopDuringPrepareAbandonsIt() async throws {
        let server = try TestHTTPServer()
        let slow = server.url("hevc10_eac3.mkv").appending(queryItems: [URLQueryItem(name: "slow", value: "1")])
        let engine = engine()
        let loading = Task { try await engine.prepare(source: MediaSource(url: slow, headers: TestHTTPServer.authHeaders),
                                                      startAt: 0) }
        try await Task.sleep(nanoseconds: 300_000_000)
        engine.stop()
        do {
            try await loading.value
            XCTFail("prepare finished after stop: \(engine.state)")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(engine.state, .idle)

        // Cancelling the loading task (the player closing) ends it the same way, not as a failure.
        let cancelled = Task { try await engine.prepare(source: MediaSource(url: slow, headers: TestHTTPServer.authHeaders),
                                                        startAt: 0) }
        try await Task.sleep(nanoseconds: 300_000_000)
        cancelled.cancel()
        _ = try? await cancelled.value
        if case .failed(let message) = engine.state { XCTFail(message) }
        engine.stop()
    }

    func testEmbeddedSubtitlesFollowTheClock() async throws {
        let engine = engine()
        defer { engine.stop() }
        try await engine.prepare(source: MediaSource(url: try Fixtures.url("subs.mkv")), startAt: 0)
        let srt = try XCTUnwrap(engine.tracks.first { $0.kind == .subtitle && $0.codec == "subrip" })
        engine.selectEmbeddedSubtitle(trackId: srt.id)
        engine.play()
        _ = await waitFor(8) { engine.subtitleText(at: 5.0) != nil }   // reader has passed the last cue
        XCTAssertEqual(engine.subtitleText(at: 1.2), "Hello there.")
        XCTAssertEqual(engine.subtitleText(at: 5.0), "Last one.")
        engine.setExternalSubtitles([SubtitleCue(start: 0, end: 10, text: "External")])
        XCTAssertEqual(engine.subtitleText(at: 1.2), "External")
        engine.setExternalSubtitles(nil)
        engine.selectEmbeddedSubtitle(trackId: nil)
        XCTAssertNil(engine.subtitleText(at: 1.2))
    }

    /// Prepare-then-splice: the clock keeps running through the switch.
    func testSeamlessSwitch() async throws {
        try await assertSeamlessSwitch(to: MediaSource(url: try Fixtures.url("h264_aac_low.mp4")))
    }

    /// Switching into a Jellyfin transcode: its segments are stamped 10 s late, and the offset that
    /// undoes it must apply to the packets but not to where the seek lands. With the wrong
    /// timeline the splice point is 10 s ahead of the picture, the old stream runs out before
    /// reaching it, and the clock stalls and then jumps — which is what this asserts against.
    func testSwitchIntoJellyfinHLSKeepsTheClock() async throws {
        let server = try TestHTTPServer()
        try await assertSeamlessSwitch(to: MediaSource(url: server.url("hls-jellyfin/main.m3u8"),
                                                       headers: TestHTTPServer.authHeaders, timelineOffset: -10))
    }

    func assertSeamlessSwitch(to target: MediaSource, file: StaticString = #filePath, line: UInt = #line) async throws {
        let engine = engine()
        defer { engine.stop() }
        try await engine.prepare(source: MediaSource(url: try Fixtures.url("h264_aac.mp4")), startAt: 0)
        engine.play()
        _ = await waitFor(3) { engine.currentTime > 0.5 }
        let before = engine.currentTime

        final class Recorder: @unchecked Sendable {
            let lock = NSLock()
            var samples: [(Date, Double)] = []
            var states: [EngineState] = []
            func record(_ time: Double, _ state: EngineState) {
                lock.lock(); samples.append((Date(), time)); states.append(state); lock.unlock()
            }
        }
        let recorder = Recorder()
        let sampler = Task.detached {
            while !Task.isCancelled {
                recorder.record(engine.currentTime, engine.state)
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        try await engine.switchSource(target, startAt: engine.currentTime + 1)
        try await Task.sleep(nanoseconds: 300_000_000)
        sampler.cancel()
        _ = await sampler.value
        let samples = recorder.samples
        let states = recorder.states

        XCTAssertFalse(states.contains(.buffering), "playback stalled during the switch: \(engine.debugSummary)", file: file, line: line)
        // The clock never stood still for more than 100 ms and never jumped.
        var longestStall = 0.0
        var stallStart: Date?
        for (a, b) in zip(samples, samples.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.1, a.1 - 0.001, "clock went backwards", file: file, line: line)
            XCTAssertLessThan(b.1 - a.1, 0.5, "clock jumped", file: file, line: line)
            if b.1 - a.1 < 0.001 {
                stallStart = stallStart ?? a.0
                longestStall = max(longestStall, b.0.timeIntervalSince(stallStart!))
            } else {
                stallStart = nil
            }
        }
        XCTAssertLessThan(longestStall, 0.1, "clock stood still for \(longestStall) s", file: file, line: line)
        XCTAssertGreaterThan(engine.currentTime, before, file: file, line: line)
        XCTAssertNotEqual(engine.videoRenderer.status, .failed, file: file, line: line)
        XCTAssertEqual(engine.duration ?? 0, 6, accuracy: 0.5, "duration is in item time after the switch",
                       file: file, line: line)
    }

    func testFailedSwitchKeepsPlaying() async throws {
        let engine = engine()
        defer { engine.stop() }
        try await engine.prepare(source: MediaSource(url: try Fixtures.url("h264_aac.mp4")), startAt: 0)
        engine.play()
        _ = await waitFor(3) { engine.currentTime > 0.5 }
        do {
            try await engine.switchSource(MediaSource(url: URL(fileURLWithPath: "/nonexistent.mkv")), startAt: 1)
            XCTFail("expected failure")
        } catch {}
        let t = engine.currentTime
        let advancing = await waitFor(2) { engine.currentTime > t + 0.3 }
        XCTAssertTrue(advancing)
        XCTAssertEqual(engine.state, .playing)
    }
}

final class VideoFormatTests: XCTestCase {
    func info(_ name: String) throws -> VideoStreamInfo {
        let demuxer = try openDemuxer(try Fixtures.url(name))
        return VideoStreamInfo(parameters: demuxer.codecParameters(0)!)
    }

    func ext(_ format: VideoFormat, _ key: CFString) -> Any? {
        CMFormatDescriptionGetExtension(format.description, extensionKey: key)
    }

    func testHDR10Extensions() throws {
        let format = try VideoFormat.make(try info("hdr10.mkv"), firstKeyframe: nil, allowDolbyVision: true)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(format.description), kCMVideoCodecType_HEVC)
        XCTAssertEqual(ext(format, kCMFormatDescriptionExtension_TransferFunction) as? String,
                       kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String)
        XCTAssertEqual(ext(format, kCMFormatDescriptionExtension_ColorPrimaries) as? String,
                       kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String)
        XCTAssertEqual(ext(format, kCMFormatDescriptionExtension_YCbCrMatrix) as? String,
                       kCMFormatDescriptionYCbCrMatrix_ITU_R_2020 as String)
        XCTAssertFalse(format.convertAnnexB)
    }

    func testHLGTransfer() {
        var color = VideoColorInfo()
        color.transfer = 18
        color.primaries = 9
        let ext = VideoFormat.colorExtensions(color)
        XCTAssertEqual(ext[kCMFormatDescriptionExtension_TransferFunction as String] as? String,
                       kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
    }

    func dolbyVisionInfo(profile: UInt8) throws -> VideoStreamInfo {
        var info = try info("hevc10_eac3.mkv")
        info.dolbyVision = DolbyVisionConfig(versionMajor: 1, versionMinor: 0, profile: profile, level: 6,
                                             rpuPresent: true, elPresent: profile == 7, blPresent: true,
                                             blSignalCompatibilityId: profile == 5 ? 0 : 1)
        return info
    }

    func testDolbyVisionProfile8() throws {
        let format = try VideoFormat.make(try dolbyVisionInfo(profile: 8), firstKeyframe: nil, allowDolbyVision: true)
        XCTAssertTrue(format.usesDolbyVision)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(format.description), kCMVideoCodecType_DolbyVisionHEVC)
        let atoms = ext(format, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Any]
        XCTAssertNotNil(atoms?["dvvC"])
        XCTAssertNotNil(atoms?["hvcC"])
    }

    func testDolbyVisionProfile5UsesDvcC() throws {
        let format = try VideoFormat.make(try dolbyVisionInfo(profile: 5), firstKeyframe: nil, allowDolbyVision: true)
        let atoms = ext(format, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Any]
        XCTAssertNotNil(atoms?["dvcC"])
    }

    func testDolbyVisionProfile7PlaysBaseLayer() throws {
        let format = try VideoFormat.make(try dolbyVisionInfo(profile: 7), firstKeyframe: nil, allowDolbyVision: true)
        XCTAssertFalse(format.usesDolbyVision)
        XCTAssertTrue(format.stripEnhancementLayer)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(format.description), kCMVideoCodecType_HEVC)
    }

    func testDolbyVisionFallback() throws {
        let format = try VideoFormat.make(try dolbyVisionInfo(profile: 8), firstKeyframe: nil, allowDolbyVision: false)
        XCTAssertFalse(format.usesDolbyVision)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(format.description), kCMVideoCodecType_HEVC)
    }

    func testAnnexBFormatFromFirstKeyframe() throws {
        let demuxer = try openDemuxer(try Fixtures.url("annexb.ts"))
        let info = VideoStreamInfo(parameters: demuxer.codecParameters(0)!)
        var keyframe: Packet?
        while keyframe == nil, let p = try demuxer.readPacket() {
            if p.streamIndex == 0 && p.isKeyframe { keyframe = p }
        }
        let format = try VideoFormat.make(info, firstKeyframe: keyframe!.data, allowDolbyVision: true)
        XCTAssertTrue(format.convertAnnexB)
        let payload = format.payload(keyframe!.data)
        XCTAssertNotEqual(Array(payload.prefix(4)), [0, 0, 0, 1], "converted to length prefixes")
    }

    func testCapabilities() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("the simulator has no hardware video decoders")
        #else
        let caps = EngineCapabilities.current()
        XCTAssertTrue(caps.hevc, "every macOS 14 Mac and every iOS 17 iPhone decodes HEVC in hardware")
        #endif
    }
}
#endif
