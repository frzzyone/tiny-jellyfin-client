import XCTest
@testable import PlayerCore

final class DemuxerTests: XCTestCase {
    override class func setUp() { FFmpegLog.configure() }

    func testOpenMP4() throws {
        let demuxer = try openDemuxer(try Fixtures.url("h264_aac.mp4"))
        XCTAssertEqual(demuxer.tracks.map(\.kind), [.video, .audio])
        XCTAssertEqual(demuxer.tracks.map(\.codec), ["h264", "aac"])
        XCTAssertEqual(demuxer.duration ?? 0, 6, accuracy: 0.2)
        let packets = try readAll(demuxer)
        XCTAssertGreaterThan(packets.filter { $0.streamIndex == 0 }.count, 140)
        XCTAssertTrue(packets.first { $0.streamIndex == 0 }!.isKeyframe)
    }

    func testOpenMKVWithSubtitleTracks() throws {
        let demuxer = try openDemuxer(try Fixtures.url("subs.mkv"))
        let subs = demuxer.tracks.filter { $0.kind == .subtitle }
        XCTAssertEqual(subs.map(\.codec), ["subrip", "ass"])
        XCTAssertEqual(subs.map(\.language), ["eng", "spa"])
        XCTAssertEqual(subs[1].title, "Signs")
        XCTAssertTrue(subs[0].isDefault)
        XCTAssertTrue(subs.allSatisfy(\.isTextSubtitle))
    }

    func testVideoStreamInfoForHEVC10() throws {
        let demuxer = try openDemuxer(try Fixtures.url("hevc10_eac3.mkv"))
        let info = VideoStreamInfo(parameters: demuxer.codecParameters(0)!)
        XCTAssertEqual(info.codec, .hevc)
        XCTAssertEqual(info.bitDepth, 10)
        XCTAssertEqual(info.width, 320)
        XCTAssertTrue(info.hasConfigurationRecord, "MKV stores hvcC")
        XCTAssertEqual(info.color.transferKind, .sdr)
        XCTAssertNil(info.dolbyVision)
    }

    func testHDR10Metadata() throws {
        let demuxer = try openDemuxer(try Fixtures.url("hdr10.mkv"))
        let info = VideoStreamInfo(parameters: demuxer.codecParameters(0)!)
        #if os(Linux)
        // The system FFmpeg decodes the SPS during probing; our macOS build has no video
        // decoders, so there VideoFormat infers colour from the parameter sets instead.
        XCTAssertEqual(info.color.transferKind, .pq)
        XCTAssertEqual(info.color.primaries, 9)  // BT.2020
        XCTAssertEqual(info.color.matrix, 9)     // BT.2020 NCL
        #endif
        if let mdcv = info.color.masteringDisplay {
            XCTAssertEqual(mdcv.count, 24)
            // Green x = 13250 (0.265 * 50000) first, per SEI order.
            XCTAssertEqual(UInt16(mdcv[0]) << 8 | UInt16(mdcv[1]), 13250)
            // Max luminance 1000 cd/m² = 10,000,000 in 0.0001 units.
            let maxLum = mdcv[16..<20].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            XCTAssertEqual(maxLum, 10_000_000)
        }
        if let clli = info.color.contentLightLevel {
            XCTAssertEqual(Array(clli), [0x03, 0xE8, 0x01, 0x90])  // 1000, 400
        }
    }

    func testAnnexBStream() throws {
        let demuxer = try openDemuxer(try Fixtures.url("annexb.ts"))
        let info = VideoStreamInfo(parameters: demuxer.codecParameters(0)!)
        XCTAssertEqual(info.codec, .h264)
        XCTAssertFalse(info.hasConfigurationRecord)
        let packet = try XCTUnwrap(try readAll(demuxer).first { $0.streamIndex == 0 && $0.isKeyframe })
        XCTAssertTrue(NALUnits.isAnnexB(packet.data))
        let sets = NALUnits.parameterSets(NALUnits.splitAnnexB(packet.data), codec: .h264)
        XCTAssertEqual(sets.map { NALUnits.type(of: $0, codec: .h264) }, [7, 8])
    }

    func testSeekLandsOnKeyframeBeforeTarget() throws {
        let demuxer = try openDemuxer(try Fixtures.url("h264_aac.mp4"))
        for target in [1.5, 4.2, 0.3, 3.0] {
            try demuxer.seek(to: target)
            let first = try XCTUnwrap(try demuxer.readPacket().flatMap { p -> Packet? in
                var p: Packet? = p
                while let current = p, current.streamIndex != 0 { p = try demuxer.readPacket() }
                return p
            })
            XCTAssertTrue(first.isKeyframe)
            XCTAssertLessThanOrEqual(first.time, target + 0.05)
            XCTAssertGreaterThan(first.time, target - 1.05, "keyframes are 1 s apart")
        }
    }

    func testInterruptStopsPromptlyOnClose() throws {
        let server = try TestHTTPServer()
        let demuxer = try openDemuxer(server.url("hevc10_eac3.mkv"), headers: TestHTTPServer.authHeaders)
        let total = try readAll(try openDemuxer(try Fixtures.url("hevc10_eac3.mkv"))).count
        let start = Date()
        demuxer.interrupt()
        var read = 0
        var interrupted = false
        do {
            while try demuxer.readPacket() != nil { read += 1 }
        } catch {
            interrupted = true
        }
        XCTAssertTrue(interrupted)
        XCTAssertLessThan(read, total, "reading stops before the end of the file")
        demuxer.close()
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    func testCorruptFileIsReadable() throws {
        let demuxer = try openDemuxer(try Fixtures.url("corrupt.mkv"))
        var count = 0
        while true {
            do {
                guard try demuxer.readPacket() != nil else { break }
                count += 1
            } catch {
                break
            }
        }
        XCTAssertGreaterThan(count, 100, "reading continues past the damaged section")
    }

    func testTruncatedFileEnds() throws {
        let demuxer = try openDemuxer(try Fixtures.url("truncated.mkv"))
        var count = 0
        do { while try demuxer.readPacket() != nil { count += 1 } } catch {}
        XCTAssertGreaterThan(count, 10)
    }
}

final class HTTPTests: XCTestCase {
    override class func setUp() { FFmpegLog.configure() }

    func testHTTPRangeReadsAndSeeks() throws {
        let server = try TestHTTPServer()
        let source = HTTPByteSource(url: server.url("h264_aac.mp4"), headers: TestHTTPServer.authHeaders,
                                    session: HTTPByteSource.makeSession())
        let local = try Data(contentsOf: try Fixtures.url("h264_aac.mp4"))
        let head = try source.read(at: 0, maxLength: 1000)
        XCTAssertEqual(head, local.prefix(1000))
        XCTAssertEqual(source.size, Int64(local.count))
        let middle = try source.read(at: 100_000, maxLength: 500)   // far seek → new Range request
        XCTAssertEqual(middle, local.subdata(in: 100_000..<100_500))
        let back = try source.read(at: 10, maxLength: 10)
        XCTAssertEqual(back, local.subdata(in: 10..<20))
        XCTAssertEqual(try source.read(at: Int64(local.count), maxLength: 10), Data())
    }

    func testAuthorizationHeaderIsSent() throws {
        let server = try TestHTTPServer()
        let source = HTTPByteSource(url: server.url("h264_aac.mp4"), headers: [:], session: HTTPByteSource.makeSession())
        XCTAssertThrowsError(try source.read(at: 0, maxLength: 10)) { error in
            XCTAssertEqual((error as? HTTPStatusError)?.status, 401)
        }
    }

    func testServerIgnoringRangeStillWorks() throws {
        let server = try TestHTTPServer()
        var components = URLComponents(url: server.url("h264_aac.mp4"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "norange", value: "1")]
        let source = HTTPByteSource(url: components.url!, headers: TestHTTPServer.authHeaders,
                                    session: HTTPByteSource.makeSession())
        let local = try Data(contentsOf: try Fixtures.url("h264_aac.mp4"))
        XCTAssertEqual(try source.read(at: 50_000, maxLength: 100), local.subdata(in: 50_000..<50_100))
    }

    func testDroppedConnectionIsRetried() throws {
        let server = try TestHTTPServer()
        var components = URLComponents(url: server.url("hevc10_eac3.mkv"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "drop", value: "30000")]
        let source = HTTPByteSource(url: components.url!, headers: TestHTTPServer.authHeaders,
                                    session: HTTPByteSource.makeSession())
        source.retryDelays = [0.1, 0.2, 0.4]
        let local = try Data(contentsOf: try Fixtures.url("hevc10_eac3.mkv"))
        var offset: Int64 = 0
        var collected = Data()
        while offset < 200_000 {
            let chunk = try source.read(at: offset, maxLength: 16_384)
            if chunk.isEmpty { break }
            collected.append(chunk)
            offset += Int64(chunk.count)
        }
        XCTAssertEqual(collected, local.prefix(collected.count))
        XCTAssertGreaterThanOrEqual(collected.count, 200_000)
    }

    func testParksWhenFarAheadAndResumes() throws {
        let server = try TestHTTPServer()
        let source = HTTPByteSource(url: server.url("hevc10_eac3.mkv"), headers: TestHTTPServer.authHeaders,
                                    session: HTTPByteSource.makeSession())
        source.maxBuffered = 64 * 1024
        let local = try Data(contentsOf: try Fixtures.url("hevc10_eac3.mkv"))
        var collected = try source.read(at: 0, maxLength: 1000)
        Thread.sleep(forTimeInterval: 0.3)   // the download runs ahead, fills the buffer and parks
        var offset = Int64(collected.count)
        while true {
            let chunk = try source.read(at: offset, maxLength: 32 * 1024)
            if chunk.isEmpty { break }
            collected.append(chunk)
            offset += Int64(chunk.count)
        }
        XCTAssertEqual(collected, local, "parking and resuming must not lose or duplicate bytes")
    }

    func testCancelUnblocksRead() throws {
        let server = try TestHTTPServer()
        let source = HTTPByteSource(url: server.url("h264_aac.mp4"), headers: TestHTTPServer.authHeaders,
                                    session: HTTPByteSource.makeSession())
        source.cancel()  // cancelling before a read only affects reads in flight
        XCTAssertFalse(try source.read(at: 0, maxLength: 10).isEmpty)
        let done = expectation(description: "read returns")
        DispatchQueue.global().async {
            // Reads past what is buffered keep the source busy; cancel must end them.
            _ = try? source.read(at: 10_000_000, maxLength: 10)
            done.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.2)
        source.cancel()
        wait(for: [done], timeout: 2)
    }

    /// `seekBeforeProbe` must position the input before `find_stream_info`, so probing reads the
    /// target. For HLS that is what stops the server transcoding the start of the item as well.
    func testPreProbeSeekPositionsSegmentedInput() throws {
        let server = try TestHTTPServer()
        let demuxer = Demuxer(url: server.url("hls/main.m3u8"), factory:
                                DefaultByteSourceFactory(headers: TestHTTPServer.authHeaders))
        try demuxer.open(seekBeforeProbe: 4.0)
        XCTAssertEqual(demuxer.tracks.filter { $0.kind != .other }.map(\.codec), ["h264", "aac"],
                       "stream info is still complete when probing starts at the target")
        // No seek afterwards for a segmented input: reading begins where probing left it, which is
        // at or after the target — never back at the start of the stream.
        var packet = try demuxer.readPacket()
        while let p = packet, p.streamIndex != 0 { packet = try demuxer.readPacket() }
        let first = try XCTUnwrap(packet)
        XCTAssertGreaterThan(first.time, 1.5, "started near the target, not at the beginning")
        XCTAssertLessThan(first.time, 4.0 + 4.0, "within a segment or two of the target")
    }

    /// An unsegmented input is repositioned after probing, so reading starts at the keyframe at or
    /// before the target rather than wherever probing stopped.
    func testPreProbeSeekRepositionsUnsegmentedInput() throws {
        let server = try TestHTTPServer()
        let demuxer = Demuxer(url: server.url("hevc10_eac3.mkv"), factory:
                                DefaultByteSourceFactory(headers: TestHTTPServer.authHeaders))
        try demuxer.open(seekBeforeProbe: 4.0)
        XCTAssertFalse(demuxer.isSegmented)
        var packet = try demuxer.readPacket()
        while let p = packet, p.streamIndex != 0 { packet = try demuxer.readPacket() }
        let first = try XCTUnwrap(packet)
        XCTAssertLessThanOrEqual(first.time, 4.05, "repositioned to the keyframe at or before 4 s")
        XCTAssertGreaterThan(first.time, 2.0)
    }

    func testSeekOverHTTP() throws {
        let server = try TestHTTPServer()
        let demuxer = try openDemuxer(server.url("hevc10_eac3.mkv"), headers: TestHTTPServer.authHeaders)
        XCTAssertTrue(demuxer.isSeekable, "HTTP input must be seekable so seeks use Range requests")
        try demuxer.seek(to: 4.2)
        var packet = try demuxer.readPacket()
        while let p = packet, p.streamIndex != 0 { packet = try demuxer.readPacket() }
        let first = try XCTUnwrap(packet)
        XCTAssertLessThanOrEqual(first.time, 4.25)
        XCTAssertGreaterThan(first.time, 3.0, "seek landed near the target instead of reading from the start")
    }

    func testDemuxOverHTTP() throws {
        let server = try TestHTTPServer()
        let demuxer = try openDemuxer(server.url("hevc10_eac3.mkv"), headers: TestHTTPServer.authHeaders)
        XCTAssertEqual(demuxer.tracks.map(\.codec), ["hevc", "eac3"])
        XCTAssertGreaterThan(try readAll(demuxer).count, 100)
    }

    func testHLSPlaylistThroughIOOpen() throws {
        let server = try TestHTTPServer()
        let demuxer = try openDemuxer(server.url("hls/main.m3u8"), headers: TestHTTPServer.authHeaders)
        XCTAssertEqual(demuxer.tracks.filter { $0.kind != .other }.map(\.codec), ["h264", "aac"])
        XCTAssertEqual(demuxer.duration ?? 0, 6, accuracy: 0.5)
        let packets = try readAll(demuxer)
        let videoTimes = packets.filter { $0.streamIndex == 0 }.map(\.time)
        XCTAssertGreaterThan(videoTimes.count, 140)
        XCTAssertGreaterThan(videoTimes.max() ?? 0, 5.5, "all segments were fetched")
        // Seek back after reaching the end, and forward again.
        for target in [2.2, 4.1] {
            try demuxer.seek(to: target)
            var next = try demuxer.readPacket()
            while let packet = next, !packet.hasTimestamp { next = try demuxer.readPacket() }
            let afterSeek = try XCTUnwrap(next, "seek to \(target)")
            XCTAssertLessThanOrEqual(afterSeek.time, target + 0.1)
            XCTAssertGreaterThan(afterSeek.time, target - 2.1, "within one segment")
        }
    }

    func testFFmpegURLMapping() {
        let mapped = MediaIO.ffmpegURL(for: URL(string: "https://jf.example.com:8920/videos/x/master.m3u8?a=1")!)
        XCTAssertEqual(mapped, "http://jf.example.com:8920/videos/x/master.m3u8?a=1")
        let io = MediaIO(factory: DefaultByteSourceFactory(), realScheme: "https")
        XCTAssertEqual(io.realURL(fromFFmpeg: "http://jf.example.com:8920/videos/x/hls1/main/0.mp4")?.absoluteString,
                       "https://jf.example.com:8920/videos/x/hls1/main/0.mp4")
        XCTAssertEqual(MediaIO.ffmpegURL(for: URL(fileURLWithPath: "/tmp/a.mkv")), "file:///tmp/a.mkv")
    }
}

final class PacketQueueTests: XCTestCase {
    func packets(_ demuxer: Demuxer, stream: Int, count: Int) throws -> [Packet] {
        var result: [Packet] = []
        while result.count < count, let p = try demuxer.readPacket() {
            if p.streamIndex == stream { result.append(p) }
        }
        return result
    }

    func testBoundedByDuration() throws {
        let demuxer = try openDemuxer(try Fixtures.url("h264_aac.mp4"))
        let video = try packets(demuxer, stream: 0, count: 100)
        let queue = PacketQueue(maxDuration: 1.0)
        let lock = NSLock()
        var pushed = 0
        let done = expectation(description: "producer ends")
        DispatchQueue.global().async {
            for packet in video {
                if !queue.push(packet) { break }
                lock.lock(); pushed += 1; lock.unlock()
            }
            done.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.3)
        lock.lock(); let count = pushed; lock.unlock()
        XCTAssertLessThan(count, 40, "push blocks once a second is buffered")
        XCTAssertLessThanOrEqual(queue.duration, 1.05)
        XCTAssertNotNil(queue.pop())
        queue.close()
        wait(for: [done], timeout: 2)
        queue.flush()
        XCTAssertTrue(queue.isEmpty)
        queue.markEndOfStream()
        XCTAssertTrue(queue.isDrained)
    }

    func testCloseUnblocksPush() throws {
        let demuxer = try openDemuxer(try Fixtures.url("h264_aac.mp4"))
        let video = try packets(demuxer, stream: 0, count: 60)
        let queue = PacketQueue(maxDuration: 0.5)
        let done = expectation(description: "push loop ends")
        DispatchQueue.global().async {
            for packet in video where !queue.push(packet) { break }
            done.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.1)
        queue.close()
        wait(for: [done], timeout: 2)
    }

    func testDropWhile() throws {
        let demuxer = try openDemuxer(try Fixtures.url("h264_aac.mp4"))
        let queue = PacketQueue()
        for packet in try packets(demuxer, stream: 0, count: 48) { queue.push(packet) }
        queue.dropWhile { $0.time < 1.0 }
        XCTAssertGreaterThanOrEqual(queue.peek()?.time ?? 0, 1.0 - 0.001)
    }
}
