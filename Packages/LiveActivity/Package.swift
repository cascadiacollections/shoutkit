// swift-tools-version: 6.4

import PackageDescription

/// Release builds of this package optimize for size, not speed (DECISIONS.md,
/// 2026-11-07). A project-level `SWIFT_OPTIMIZATION_LEVEL` never reaches package
/// targets, so this is the only place it can be set. `unsafeFlags` is allowed
/// because the package is only ever consumed by path from this repository.
let optimizeForSize: SwiftSetting = .unsafeFlags(["-Osize"], .when(configuration: .release))

let package = Package(
    name: "LiveActivity",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        // The App Group stores — linked by BOTH the app and the widget
        // extension. Kept dependency-free so the extension stays lean.
        //
        // The package and product names predate the Live Activity's removal
        // (DECISIONS.md, 2026-11-14); what remains serves the Home Screen widget.
        .library(name: "NowPlayingActivityCore", targets: ["NowPlayingActivityCore"]),
        // App-side coordinator that keeps the widget's snapshot in step with playback.
        .library(name: "NowPlayingActivityKit", targets: ["NowPlayingActivityKit"]),
    ],
    dependencies: [
        .package(path: "../ImageIODownsample"),
        .package(path: "../Playback"),
        .package(path: "../RadioDirectory"),
    ],
    targets: [
        .target(name: "NowPlayingActivityCore", swiftSettings: [optimizeForSize]),
        .target(
            name: "NowPlayingActivityKit",
            dependencies: [
                "NowPlayingActivityCore",
                .product(name: "ImageIODownsample", package: "ImageIODownsample"),
                .product(name: "Playback", package: "Playback"),
                .product(name: "RadioDirectory", package: "RadioDirectory"),
            ],
            swiftSettings: [optimizeForSize],
        ),
        .testTarget(
            name: "NowPlayingActivityCoreTests",
            dependencies: ["NowPlayingActivityCore"],
        ),
        // iOS-only like the rest of the package, so it runs in the simulator
        // through HolmdelApp/Holmdel.xctestplan, not under `swift test`.
        .testTarget(
            name: "NowPlayingActivityKitTests",
            dependencies: ["NowPlayingActivityKit"],
        ),
    ],
)
