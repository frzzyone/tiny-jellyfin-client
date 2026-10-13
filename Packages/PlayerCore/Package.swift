// swift-tools-version:5.10
import Foundation
import PackageDescription

// FFmpeg comes from the system on Linux (development/tests of the portable core) and from our own
// LGPL build on Apple platforms: Vendor/FFmpeg/FFmpeg.xcframework (macOS, iOS, iOS Simulator), linked
// as a binary target through the FFmpeg.xcframework symlink here, with headers in Vendor/FFmpeg/include.
// See scripts/build-ffmpeg.sh.
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let vendor = packageDir.appendingPathComponent("../../Vendor/FFmpeg").standardizedFileURL.path

#if os(Linux)
let ffmpegC: [CSetting] = []
let ffmpegSwift: [SwiftSetting] = []
let ffmpegLink: [LinkerSetting] = ["avformat", "avcodec", "avutil", "swresample"].map { .linkedLibrary($0) }
let ffmpegTargets: [Target] = []
let ffmpegDeps: [Target.Dependency] = []
#else
let ffmpegC: [CSetting] = [.unsafeFlags(["-I\(vendor)/include"])]
let ffmpegSwift: [SwiftSetting] = [.unsafeFlags(["-Xcc", "-I\(vendor)/include"])]
let ffmpegLink: [LinkerSetting] = []
let ffmpegTargets: [Target] = [.binaryTarget(name: "FFmpeg", path: "FFmpeg.xcframework")]
let ffmpegDeps: [Target.Dependency] = ["FFmpeg"]
#endif

let package = Package(
    name: "PlayerCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "PlayerCore", targets: ["PlayerCore"]),
    ],
    targets: ffmpegTargets + [
        .target(name: "CFFmpeg", dependencies: ffmpegDeps, cSettings: ffmpegC, linkerSettings: ffmpegLink),
        .target(name: "PlayerCore", dependencies: ["CFFmpeg"], swiftSettings: ffmpegSwift),
        .testTarget(name: "PlayerCoreTests", dependencies: ["PlayerCore"],
                    resources: [.copy("Fixtures")], swiftSettings: ffmpegSwift),
    ]
)
