// swift-tools-version:5.10
import Foundation
import PackageDescription

// FFmpeg comes from the system on Linux (development/tests of the portable core) and from
// our own LGPL build in Vendor/FFmpeg on macOS (see scripts/build-ffmpeg.sh).
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let vendor = packageDir.appendingPathComponent("../../Vendor/FFmpeg").standardizedFileURL.path

#if os(Linux)
let ffmpegC: [CSetting] = []
let ffmpegSwift: [SwiftSetting] = []
let ffmpegLink: [LinkerSetting] = ["avformat", "avcodec", "avutil", "swresample"].map { .linkedLibrary($0) }
#else
let ffmpegC: [CSetting] = [.unsafeFlags(["-I\(vendor)/include"])]
let ffmpegSwift: [SwiftSetting] = [.unsafeFlags(["-Xcc", "-I\(vendor)/include"])]
let ffmpegLink: [LinkerSetting] = [
    .linkedLibrary("ffmpeg"),
    .unsafeFlags(["-L\(vendor)/lib", "-Xlinker", "-rpath", "-Xlinker", "\(vendor)/lib"]),
]
#endif

let package = Package(
    name: "PlayerCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PlayerCore", targets: ["PlayerCore"]),
    ],
    targets: [
        .target(name: "CFFmpeg", cSettings: ffmpegC, linkerSettings: ffmpegLink),
        .target(name: "PlayerCore", dependencies: ["CFFmpeg"], swiftSettings: ffmpegSwift),
        .testTarget(name: "PlayerCoreTests", dependencies: ["PlayerCore"],
                    resources: [.copy("Fixtures")], swiftSettings: ffmpegSwift),
    ]
)
