// swift-tools-version: 6.4

import PackageDescription

/// Release builds of this package optimize for size, not speed (DECISIONS.md,
/// 2026-11-07). A project-level `SWIFT_OPTIMIZATION_LEVEL` never reaches package
/// targets, so this is the only place it can be set. `unsafeFlags` is allowed
/// because the package is only ever consumed by path from this repository.
let optimizeForSize: SwiftSetting = .unsafeFlags(["-Osize"], .when(configuration: .release))

/// The app's Nuke-backed artwork pipeline: memory cache, disk cache, in-flight
/// coalescing, and ImageIO thumbnail decoding for station logos and Now
/// Playing art.
///
/// App-side, like `DebugSupport` and `PlaybackEngineAudioStreaming`, so the
/// MIT `DesignSystem` package carries no Nuke dependency and none of this
/// app's names (the disk cache directory, the speculative-lane header).
/// `DesignSystem` exposes `ArtworkImageSource.register(_:)`; the app target
/// registers this pipeline there during `bootstrap()`. Without that call,
/// `DesignSystem` falls back to an uncached fetch-and-downsample, which is what
/// previews, package tests, and outside adopters get.
///
/// No `LICENSE` file: like the app target, this is GPL-3.0 (README, Licensing).
/// It does not depend on `DesignSystem`, which is what lets its suite run under
/// `swift test` on the mac host — `DesignSystem` declares `.iOS` alone.
let package = Package(
    name: "ArtworkPipelineNuke",
    platforms: [
        .iOS(.v26),
        .macOS(.v13),
    ],
    products: [
        .library(name: "ArtworkPipelineNuke", targets: ["ArtworkPipelineNuke"]),
    ],
    dependencies: [
        .package(path: "../RadioDirectory"),
        .package(url: "https://github.com/kean/Nuke.git", exact: "13.2.3"),
    ],
    targets: [
        .target(
            name: "ArtworkPipelineNuke",
            dependencies: [
                "RadioDirectory",
                .product(name: "Nuke", package: "Nuke"),
            ],
            swiftSettings: [optimizeForSize],
        ),
        .testTarget(
            name: "ArtworkPipelineNukeTests",
            dependencies: ["ArtworkPipelineNuke"],
        ),
    ],
)
