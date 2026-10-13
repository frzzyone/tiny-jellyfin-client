import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JellyfinKit

final class QualityTests: XCTestCase {
    func labels(_ height: Int?) -> [String] { QualitySelection.visibleOptions(sourceHeight: height).map(\.label) }

    func test1080pSourceHides4K() {
        XCTAssertEqual(labels(1080), ["Original", "1080p 20 Mbps", "1080p 10 Mbps", "720p 4 Mbps",
                                      "480p 1.5 Mbps", "360p 720 kbps"])
        XCTAssertEqual(labels(1072), labels(1080), "cropped 1080p counts as 1080p")
    }

    func testUnknownResolutionShowsAll() {
        XCTAssertEqual(labels(nil).count, 7)
        XCTAssertEqual(labels(0).count, 7)
    }

    func test4KSourceShowsAll() {
        XCTAssertEqual(labels(2160).count, 7)
        XCTAssertEqual(labels(1600).count, 7, "scope 4K crops")
    }

    func testDefaultIsOriginal() {
        XCTAssertEqual(QualitySelection.startingQuality(preferredId: nil, sourceHeight: 1080), .original)
    }

    func testPreferenceCarriesOver() {
        XCTAssertEqual(QualitySelection.startingQuality(preferredId: "720p-4", sourceHeight: 1080).label, "720p 4 Mbps")
    }

    func testHiddenRememberedPresetFallsBackToOriginal() {
        XCTAssertEqual(QualitySelection.startingQuality(preferredId: "2160p-40", sourceHeight: 1080), .original)
    }

    func testPreferenceStoredPerServerAndUntouchedByFallback() {
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "q-\(UUID().uuidString)")!)
        let a = URL(string: "https://a.test")!, b = URL(string: "https://b.test")!
        prefs.setPreferredQualityId("2160p-40", server: a)
        _ = QualitySelection.startingQuality(preferredId: prefs.preferredQualityId(server: a), sourceHeight: 1080)
        XCTAssertEqual(prefs.preferredQualityId(server: a), "2160p-40")
        XCTAssertNil(prefs.preferredQualityId(server: b))
    }
}

final class DeviceProfileTests: XCTestCase {
    let caps = PlaybackCapabilities(av1: true)

    func json(_ profile: DeviceProfile) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(profile)) as! [String: Any]
    }

    func testOriginalProfile() throws {
        let profile = DeviceProfileBuilder.build(capabilities: caps, quality: .original)
        let object = try json(profile)
        XCTAssertEqual(object["MaxStreamingBitrate"] as? Int, 200_000_000)
        let direct = (object["DirectPlayProfiles"] as! [[String: Any]])[0]
        XCTAssertEqual(direct["Container"] as? String, "mkv,webm,mp4,m4v,mov,ts,mpegts")
        XCTAssertEqual(direct["VideoCodec"] as? String, "h264,hevc,av1")
        XCTAssertTrue((direct["AudioCodec"] as! String).contains("truehd"))
        XCTAssertTrue((direct["AudioCodec"] as! String).contains("dts"))
        let transcoding = (object["TranscodingProfiles"] as! [[String: Any]])[0]
        XCTAssertEqual(transcoding["Protocol"] as? String, "hls")
        XCTAssertEqual(transcoding["Container"] as? String, "ts")
        XCTAssertEqual(transcoding["VideoCodec"] as? String, "hevc,h264")
        // No resolution cap for Original.
        let codecProfiles = object["CodecProfiles"] as! [[String: Any]]
        XCTAssertFalse(codecProfiles.contains { ($0["Conditions"] as! [[String: Any]]).contains { $0["Property"] as? String == "Height" } })
        // Image subtitles are burned in, text subtitles embedded or external.
        let subs = object["SubtitleProfiles"] as! [[String: Any]]
        XCTAssertTrue(subs.contains { $0["Format"] as? String == "pgssub" && $0["Method"] as? String == "Encode" })
        XCTAssertTrue(subs.contains { $0["Format"] as? String == "srt" && $0["Method"] as? String == "External" })
    }

    func test720pPresetCapsBitrateAndHeight() throws {
        let preset = QualityPreset.with(id: "720p-4")!
        let object = try json(DeviceProfileBuilder.build(capabilities: caps, quality: preset))
        XCTAssertEqual(object["MaxStreamingBitrate"] as? Int, 4_000_000)
        let conditions = (object["CodecProfiles"] as! [[String: Any]]).flatMap { $0["Conditions"] as! [[String: Any]] }
        let height = conditions.first { $0["Property"] as? String == "Height" }
        XCTAssertEqual(height?["Condition"] as? String, "LessThanEqual")
        XCTAssertEqual(height?["Value"] as? String, "720")
        XCTAssertEqual(conditions.first { $0["Property"] as? String == "Width" }?["Value"] as? String, "1280")
    }

    /// A Dolby Vision capable client must advertise the DOVI range types, or the server transcodes
    /// every DV file in full. A client without them must not.
    func testDolbyVisionRangeTypes() throws {
        let withDV = try json(DeviceProfileBuilder.build(capabilities: caps, quality: .original))
        let conditions = (withDV["CodecProfiles"] as! [[String: Any]])
            .filter { $0["Codec"] as? String == "hevc" }
            .flatMap { $0["Conditions"] as! [[String: Any]] }
        let ranges = conditions.first { $0["Property"] as? String == "VideoRangeType" }?["Value"] as? String
        XCTAssertNotNil(ranges)
        for expected in ["DOVI", "DOVIWithHDR10", "HDR10", "HLG", "SDR"] {
            XCTAssertTrue(ranges!.contains(expected), "missing \(expected) in \(ranges!)")
        }

        let noDV = PlaybackCapabilities(av1: false, hevc10Bit: true, dolbyVision: false)
        let without = try json(DeviceProfileBuilder.build(capabilities: noDV, quality: .original))
        let plainRanges = (without["CodecProfiles"] as! [[String: Any]])
            .filter { $0["Codec"] as? String == "hevc" }
            .flatMap { $0["Conditions"] as! [[String: Any]] }
            .first { $0["Property"] as? String == "VideoRangeType" }?["Value"] as? String
        XCTAssertFalse(plainRanges?.contains("DOVI") ?? true)
    }

    func testMacWithoutAV1() throws {
        let profile = DeviceProfileBuilder.build(capabilities: PlaybackCapabilities(av1: false), quality: .original)
        XCTAssertEqual(profile.directPlayProfiles[0].videoCodec, "h264,hevc")
    }
}

final class PlaybackInfoTests: XCTestCase {
    func fixture(_ sourceJSON: String, session: String = "ps1") -> PlaybackInfoResponse {
        let json = #"{"MediaSources":[\#(sourceJSON)],"PlaySessionId":"\#(session)"}"#
        return try! JSONCoding.decoder.decode(PlaybackInfoResponse.self, from: Data(json.utf8))
    }

    func testRequestBody() async throws {
        let server = StubServer()
        server.on("POST", "/Items/m1/PlaybackInfo", json: #"{"MediaSources":[],"PlaySessionId":"p"}"#)
        _ = try await server.client().playbackInfo(itemId: "m1", quality: QualityPreset.with(id: "480p-1.5")!,
                                                   capabilities: PlaybackCapabilities(av1: false),
                                                   startSeconds: 3750, mediaSourceId: "src", subtitleStreamIndex: 3)
        let body = jsonBody(server.lastRequest(path: "/Items/m1/PlaybackInfo"))
        XCTAssertEqual(body["MaxStreamingBitrate"] as? Int, 1_500_000)
        XCTAssertEqual(body["StartTimeTicks"] as? Int, 37_500_000_000)
        XCTAssertEqual(body["MediaSourceId"] as? String, "src")
        XCTAssertEqual(body["SubtitleStreamIndex"] as? Int, 3)
        XCTAssertEqual(body["UserId"] as? String, "user1")
        XCTAssertNotNil(body["DeviceProfile"] as? [String: Any])
    }

    func testDirectPlayMKV() throws {
        let server = StubServer()
        let response = fixture(#"{"Id":"src","Container":"mkv","SupportsDirectPlay":true,"SupportsDirectStream":true,"SupportsTranscoding":true}"#)
        let stream = try server.client().resolveStream(itemId: "m1", response: response, startSeconds: 0)
        XCTAssertEqual(stream.playMethod, .directPlay)
        XCTAssertEqual(stream.url.path, "/Videos/m1/stream")
        XCTAssertEqual(stream.url.query, "mediaSourceId=src&playSessionId=ps1&static=true")
        XCTAssertFalse(stream.url.absoluteString.contains("tok"), "token travels in the Authorization header, not the URL")
        XCTAssertEqual(stream.playSessionId, "ps1")
    }

    func testVC1Transcode() throws {
        let server = StubServer()
        let url = "/videos/m1/master.m3u8?MediaSourceId=src&VideoCodec=hevc,h264&AudioCodec=ac3&TranscodeReasons=VideoCodecNotSupported&PlaySessionId=ps1"
        let response = fixture(#"{"Id":"src","SupportsDirectPlay":false,"SupportsTranscoding":true,"TranscodingUrl":"\#(url)"}"#)
        let stream = try server.client().resolveStream(itemId: "m1", response: response, startSeconds: 120)
        XCTAssertEqual(stream.playMethod, .transcode)
        XCTAssertEqual(stream.url.host, server.host)
        XCTAssertEqual(stream.url.path, "/videos/m1/master.m3u8")
        XCTAssertEqual(stream.timelineOffset, -10,
                       "MPEG-TS segments are stamped 10 s late; the playlist still covers the whole item")
    }

    func testFMP4SegmentsKeepItemTime() throws {
        let server = StubServer()
        let url = "/videos/m1/master.m3u8?MediaSourceId=src&VideoCodec=hevc&AudioCodec=aac&SegmentContainer=mp4&PlaySessionId=ps1"
        let response = fixture(#"{"Id":"src","SupportsDirectPlay":false,"SupportsTranscoding":true,"TranscodingUrl":"\#(url)"}"#)
        let stream = try server.client().resolveStream(itemId: "m1", response: response, startSeconds: 120)
        XCTAssertEqual(stream.timelineOffset, 0, "only the MPEG-TS muxer adds the delay")
    }

    func testAudioOnlyConversionIsDirectStream() {
        XCTAssertEqual(PlayMethodClassifier.classify(
            transcodingUrl: "/videos/x/master.m3u8?VideoCodec=hevc&TranscodeReasons=AudioCodecNotSupported,ContainerNotSupported"),
            .directStream)
        XCTAssertEqual(PlayMethodClassifier.classify(transcodingUrl: "/videos/x/master.m3u8?VideoCodec=copy"), .directStream)
        XCTAssertEqual(PlayMethodClassifier.classify(
            transcodingUrl: "/videos/x/master.m3u8?TranscodeReasons=ContainerBitrateExceedsLimit"), .transcode)
        XCTAssertEqual(PlayMethodClassifier.classify(
            transcodingUrl: "/videos/x/master.m3u8?TranscodeReasons=SubtitleCodecNotSupported"), .transcode,
            "image-subtitle burn-in re-encodes the video")
    }

    func testNoPlayableStream() {
        let server = StubServer()
        XCTAssertThrowsError(try server.client().resolveStream(
            itemId: "m1", response: fixture(#"{"Id":"src","SupportsDirectPlay":false,"SupportsTranscoding":false}"#),
            startSeconds: 0)) { error in
            XCTAssertEqual(error as? JellyfinError, .noPlayableStream(nil))
        }
        let empty = try! JSONCoding.decoder.decode(PlaybackInfoResponse.self,
                                                   from: Data(#"{"MediaSources":[],"ErrorCode":"NoCompatibleStream"}"#.utf8))
        XCTAssertThrowsError(try server.client().resolveStream(itemId: "m1", response: empty, startSeconds: 0)) { error in
            XCTAssertEqual(error as? JellyfinError, .noPlayableStream("NoCompatibleStream"))
        }
    }
}

final class ReportingTests: XCTestCase {
    func testPayloads() async throws {
        let server = StubServer()
        for path in ["/Sessions/Playing", "/Sessions/Playing/Progress", "/Sessions/Playing/Stopped"] {
            server.on("POST", path, status: 204, json: "")
        }
        server.on("DELETE", "/Videos/ActiveEncodings", status: 204, json: "")
        let client = server.client()
        let report = PlaybackReport(itemId: "m1", mediaSourceId: "src", playSessionId: "ps1", positionSeconds: 61.5,
                                    isPaused: true, playMethod: .directStream, subtitleStreamIndex: 2)
        try await client.reportStart(report)
        try await client.reportProgress(report)
        try await client.reportStopped(report)
        try await client.endEncoding(playSessionId: "ps1")

        let body = jsonBody(server.lastRequest(path: "/Sessions/Playing/Progress"))
        XCTAssertEqual(body["PositionTicks"] as? Int, 615_000_000)
        XCTAssertEqual(body["IsPaused"] as? Bool, true)
        XCTAssertEqual(body["PlayMethod"] as? String, "DirectStream")
        XCTAssertEqual(body["PlaySessionId"] as? String, "ps1")
        XCTAssertEqual(body["MediaSourceId"] as? String, "src")
        XCTAssertEqual(body["ItemId"] as? String, "m1")
        XCTAssertNotNil(server.lastRequest(path: "/Sessions/Playing"))
        XCTAssertNotNil(server.lastRequest(path: "/Sessions/Playing/Stopped"))
        let delete = server.lastRequest(path: "/Videos/ActiveEncodings")
        XCTAssertEqual(delete?.httpMethod, "DELETE")
        XCTAssertEqual(queryValue(delete, "playSessionId"), "ps1")
        XCTAssertEqual(queryValue(delete, "deviceId"), "device-1")
    }
}

final class SubtitleSelectionTests: XCTestCase {
    func testForcedDefault() throws {
        let json = """
        {"Id":"src","DefaultSubtitleStreamIndex":4,"MediaStreams":[
          {"Type":"Subtitle","Index":3,"Codec":"subrip","Language":"eng"},
          {"Type":"Subtitle","Index":4,"Codec":"subrip","Language":"eng","IsForced":true}]}
        """
        let source = try JSONCoding.decoder.decode(MediaSourceInfo.self, from: Data(json.utf8))
        XCTAssertEqual(SubtitleSelection.defaultTrack(for: source)?.index, 4)
    }

    func testNoRecommendationMeansOff() throws {
        let source = try JSONCoding.decoder.decode(MediaSourceInfo.self, from: Data(#"{"DefaultSubtitleStreamIndex":-1}"#.utf8))
        XCTAssertNil(SubtitleSelection.defaultTrack(for: source))
    }

    func testExternalSubtitleURL() {
        let server = StubServer()
        let url = server.client().externalSubtitleURL(itemId: "m1", mediaSourceId: "src", streamIndex: 5)
        XCTAssertEqual(url.path, "/Videos/m1/src/Subtitles/5/0/Stream.srt")
    }
}
