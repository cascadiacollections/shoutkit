// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LiveActivity",
    platforms: [
        // SwiftPM's iOS platform enum does not expose a v16_1 case.
        // Keep the package at iOS 16 and gate 16.1+ ActivityKit usage with
        // @available at call sites/types.
        .iOS(.v16)
    ],
    products: [
        // Attributes only — linked by BOTH the app and the widget extension.
        // Kept dependency-free so the extension stays lean.
        .library(name: "NowPlayingActivityCore", targets: ["NowPlayingActivityCore"]),
        // App-side coordinator that drives the activity from playback state.
        .library(name: "NowPlayingActivityKit", targets: ["NowPlayingActivityKit"])
    ],
    dependencies: [
        .package(path: "../ImageIODownsample"),
        .package(path: "../Playback"),
        .package(path: "../RadioDirectory"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.1.5")
    ],
    targets: [
        .target(name: "NowPlayingActivityCore"),
        .target(
            name: "NowPlayingActivityKit",
            dependencies: [
                "NowPlayingActivityCore",
                .product(name: "ImageIODownsample", package: "ImageIODownsample"),
                .product(name: "Playback", package: "Playback"),
                .product(name: "RadioDirectory", package: "RadioDirectory"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ]
        ),
        .testTarget(
            name: "NowPlayingActivityCoreTests",
            dependencies: ["NowPlayingActivityCore"]
        )
    ]
)
