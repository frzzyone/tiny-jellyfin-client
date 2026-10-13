import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PlayerCore

enum Fixtures {
    static let directory: URL = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")

    /// Fixture URL; skips the test when fixtures were not generated (scripts/make-fixtures.sh).
    static func url(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Fixture \(name) missing — run scripts/make-fixtures.sh")
        }
        return url
    }
}

/// Runs scripts/test-http-server.py over the fixtures directory. On iOS the test process cannot
/// launch it, so scripts/test-ios.sh starts it on the host and passes its port in TEST_HTTP_PORT
/// (the simulator shares the host's network).
final class TestHTTPServer {
    let port: Int
    #if os(macOS)
    let process = Process()
    #endif

    init() throws {
        _ = try Fixtures.url("h264_aac.mp4")
        #if os(macOS)
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("../../scripts/test-http-server.py").standardizedFileURL
        guard FileManager.default.fileExists(atPath: script.path) else { throw XCTSkip("test server script missing") }
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path, Fixtures.directory.path]
        process.standardOutput = pipe
        try process.run()
        let line = String(data: pipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
        guard let port = Int(line.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            process.terminate()
            throw XCTSkip("could not start test server")
        }
        self.port = port
        #else
        guard let port = ProcessInfo.processInfo.environment["TEST_HTTP_PORT"].flatMap(Int.init) else {
            throw XCTSkip("no TEST_HTTP_PORT — run scripts/test-ios.sh")
        }
        self.port = port
        #endif
    }

    #if os(macOS)
    deinit { process.terminate() }
    #endif

    func url(_ path: String, isPublic: Bool = false) -> URL {
        URL(string: "http://127.0.0.1:\(port)/\(isPublic ? "public/" : "")\(path)")!
    }

    static let authHeaders = ["Authorization": "test"]
}

func readAll(_ demuxer: Demuxer) throws -> [Packet] {
    var packets: [Packet] = []
    while let packet = try demuxer.readPacket() { packets.append(packet) }
    return packets
}

func openDemuxer(_ url: URL, headers: [String: String] = [:]) throws -> Demuxer {
    let demuxer = Demuxer(url: url, factory: DefaultByteSourceFactory(headers: headers))
    try demuxer.open()
    return demuxer
}
