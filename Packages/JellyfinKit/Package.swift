// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "JellyfinKit",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [
        .library(name: "JellyfinKit", targets: ["JellyfinKit"]),
    ],
    targets: [
        .target(name: "JellyfinKit"),
        .testTarget(name: "JellyfinKitTests", dependencies: ["JellyfinKit"]),
    ]
)
