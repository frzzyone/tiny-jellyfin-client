import XCTest
@testable import PlayerCore

final class AudioDecoderTests: XCTestCase {
    override class func setUp() { FFmpegLog.configure() }

    /// Decodes the first audio stream of a fixture; returns frames.
    func decode(_ name: String) throws -> [AudioFrame] {
        let demuxer = try openDemuxer(try Fixtures.url(name))
        let index = try XCTUnwrap(demuxer.tracks.first { $0.kind == .audio }?.id)
        let stream = try XCTUnwrap(demuxer.stream(index))
        let decoder = try AudioDecoder(parameters: stream.pointee.codecpar, timeBase: stream.pointee.time_base,
                                       timelineOffset: 0)
        var frames: [AudioFrame] = []
        while let packet = try demuxer.readPacket() {
            if packet.streamIndex == index { frames += decoder.decode(packet) }
        }
        return frames
    }

    func assertDecodes(_ name: String, channels: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        let frames = try decode(name)
        XCTAssertFalse(frames.isEmpty, "no frames for \(name)", file: file, line: line)
        XCTAssertEqual(frames.first?.channels, channels, name, file: file, line: line)
        let total = frames.reduce(0.0) { $0 + $1.duration }
        XCTAssertEqual(total, 6, accuracy: 0.3, name, file: file, line: line)
        let first = try XCTUnwrap(frames.first)
        XCTAssertEqual(first.samples.count, first.frameCount * first.channels * 4, file: file, line: line)
        // Timestamps increase.
        XCTAssertEqual(zip(frames, frames.dropFirst()).filter { $1.pts < $0.pts }.count, 0, file: file, line: line)
    }

    func testDTS51() throws { try assertDecodes("h264_dts.mkv", channels: 6) }
    func testTrueHD51() throws { try assertDecodes("h264_truehd.mkv", channels: 6) }
    func testEAC351() throws { try assertDecodes("hevc10_eac3.mkv", channels: 6) }
    func testFLAC() throws { try assertDecodes("audio_flac.mkv", channels: 1) }
    func testOpus() throws { try assertDecodes("audio_opus.mkv", channels: 1) }
    func testVorbis() throws { try assertDecodes("audio_vorbis.mkv", channels: 1) }
    func testMP3() throws { try assertDecodes("audio_mp3.mkv", channels: 1) }
    func testPCM() throws { try assertDecodes("audio_pcm.mkv", channels: 1) }
    func testAAC() throws { try assertDecodes("audio_aac.mkv", channels: 1) }

    func testChannelMaskForFiveOne() throws {
        let frames = try decode("h264_truehd.mkv")
        // FL FR FC LFE BL BR (or side) — six bits set, includes front centre (bit 2).
        XCTAssertEqual(frames.first?.channelMask.nonzeroBitCount, 6)
        XCTAssertNotEqual((frames.first?.channelMask ?? 0) & 0x4, 0)
    }
}

final class SubtitleTests: XCTestCase {
    override class func setUp() { FFmpegLog.configure() }

    func embeddedCues(track: Int) throws -> SubtitleTrackStore {
        let demuxer = try openDemuxer(try Fixtures.url("subs.mkv"))
        let stream = try XCTUnwrap(demuxer.stream(track))
        let decoder = try SubtitleDecoder(parameters: stream.pointee.codecpar, timeBase: stream.pointee.time_base,
                                          timelineOffset: 0)
        let store = SubtitleTrackStore()
        while let packet = try demuxer.readPacket() {
            if packet.streamIndex == track { decoder.decode(packet).forEach(store.add) }
        }
        return store
    }

    func testEmbeddedSRT() throws {
        let store = try embeddedCues(track: 2)
        XCTAssertEqual(store.count, 3)
        XCTAssertNil(store.text(at: 0.5))
        XCTAssertEqual(store.text(at: 1.2), "Hello there.")
        XCTAssertEqual(store.text(at: 2.2), "Hello there.\nOverlapping line\nsecond row", "overlapping cues stack")
        XCTAssertEqual(store.text(at: 3.0), "Overlapping line\nsecond row")
        XCTAssertNil(store.text(at: 4.2))
        XCTAssertEqual(store.text(at: 5.0), "Last one.")
    }

    func testEmbeddedASSIsPlainText() throws {
        let store = try embeddedCues(track: 3)
        XCTAssertEqual(store.text(at: 2), "Styled text\nsecond line")
        XCTAssertEqual(store.text(at: 4), "Drawing gone")
    }

    func testExternalSRT() throws {
        let cues = try ExternalSubtitles.parse(try Data(contentsOf: try Fixtures.url("subs.srt")))
        XCTAssertEqual(cues.count, 3)
        XCTAssertEqual(cues[0].start, 1, accuracy: 0.01)
        XCTAssertEqual(cues[0].end, 2.5, accuracy: 0.01)
        XCTAssertEqual(cues[1].text, "Overlapping line\nsecond row")
    }

    func testExternalASS() throws {
        let cues = try ExternalSubtitles.parse(try Data(contentsOf: try Fixtures.url("subs.ass")), fileExtension: "ass")
        XCTAssertEqual(cues.map(\.text), ["Styled text\nsecond line", "Drawing gone"])
    }

    func testASSStripping() {
        XCTAssertEqual(ASSText.plainText(fromText: #"{\i1}Hi{\i0}\Nthere\hfriend"#), "Hi\nthere friend")
        XCTAssertEqual(ASSText.plainText(fromText: #"{\p1}m 0 0 l 1 1{\p0}Visible"#), "Visible")
        XCTAssertEqual(ASSText.plainText(fromEvent: "0,0,Default,,0,0,0,,Text, with comma"), "Text, with comma")
        XCTAssertEqual(ASSText.plainText(fromEvent: "Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Line"), "Line")
    }

    func testStoreOrdersOutOfOrderCues() {
        let store = SubtitleTrackStore()
        store.add(SubtitleCue(start: 5, end: 6, text: "b"))
        store.add(SubtitleCue(start: 1, end: 2, text: "a"))
        store.add(SubtitleCue(start: 1, end: 2, text: "a"))
        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(store.text(at: 1.5), "a")
        XCTAssertEqual(store.text(at: 5.5), "b")
    }
}

final class BitstreamTests: XCTestCase {
    func testAnnexBToLengthPrefixed() {
        let annexB: [UInt8] = [0, 0, 0, 1, 0x67, 1, 2, 0, 0, 1, 0x68, 3, 0, 0, 1, 0x65, 9, 9, 9]
        annexB.withUnsafeBufferPointer { buffer in
            XCTAssertTrue(NALUnits.isAnnexB(buffer))
            let units = NALUnits.splitAnnexB(buffer)
            XCTAssertEqual(units.map(Array.init), [[0x67, 1, 2], [0x68, 3], [0x65, 9, 9, 9]])
            let joined = NALUnits.joinLengthPrefixed(units)
            XCTAssertEqual(Array(joined), [0, 0, 0, 3, 0x67, 1, 2, 0, 0, 0, 2, 0x68, 3, 0, 0, 0, 4, 0x65, 9, 9, 9])
            joined.withUnsafeBytes { raw in
                let back = NALUnits.splitLengthPrefixed(raw.bindMemory(to: UInt8.self))
                XCTAssertEqual(back.count, 3)
            }
        }
    }

    func testDolbyVisionELStripping() {
        // HEVC NAL header: type in bits 1..6 of the first byte.
        let base: ArraySlice<UInt8> = [0x02, 0x01, 0xAA]       // type 1 (slice)
        let rpu: ArraySlice<UInt8> = [62 << 1, 0x01, 0xBB]     // type 62 (DV RPU)
        let el: ArraySlice<UInt8> = [63 << 1, 0x01, 0xCC]      // type 63 (DV EL)
        XCTAssertEqual(NALUnits.stripDolbyVisionEL([base, rpu, el], dropRPU: false).count, 2)
        XCTAssertEqual(NALUnits.stripDolbyVisionEL([base, rpu, el], dropRPU: true).map(Array.init), [Array(base)])
    }

    func testDolbyVisionBoxPayload() {
        // Profile 8, level 6, RPU + BL, compatibility id 1 (HDR10).
        let config = DolbyVisionConfig(versionMajor: 1, versionMinor: 0, profile: 8, level: 6, rpuPresent: true,
                                       elPresent: false, blPresent: true, blSignalCompatibilityId: 1)
        let payload = config.boxPayload
        XCTAssertEqual(payload.count, 24)
        XCTAssertEqual(Array(payload.prefix(5)), [1, 0, 0x10, 0x35, 0x10])
        XCTAssertEqual(config.boxType, "dvvC")
        XCTAssertEqual(DolbyVisionConfig(versionMajor: 1, versionMinor: 0, profile: 5, level: 6, rpuPresent: true,
                                         elPresent: false, blPresent: true, blSignalCompatibilityId: 0).boxType, "dvcC")
    }
}
