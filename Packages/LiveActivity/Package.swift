// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "LiveActivity",
    platforms: [
        .iOS(.v27)
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
