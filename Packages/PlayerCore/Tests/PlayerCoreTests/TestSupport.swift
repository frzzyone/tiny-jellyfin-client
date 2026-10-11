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

/// Runs scripts/test-http-server.py over the fixtures directory.
final class TestHTTPServer {
    let process = Process()
    let port: Int

    init() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("../../scripts/test-http-server.py").standardizedFileURL
        guard FileManager.default.fileExists(atPath: script.path) else { throw XCTSkip("test server script missing") }
        _ = try Fixtures.url("h264_aac.mp4")
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
    }

    deinit { process.terminate() }

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
