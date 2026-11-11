// swift-tools-version: 6.4

import PackageDescription

/// Release builds of this package optimize for size, not speed (DECISIONS.md,
/// 2026-11-07). A project-level `SWIFT_OPTIMIZATION_LEVEL` never reaches package
/// targets, so this is the only place it can be set. `unsafeFlags` is allowed
/// because the package is only ever consumed by path from this repository.
let optimizeForSize: SwiftSetting = .unsafeFlags(["-Osize"], .when(configuration: .release))

/// A leaf MIT package: live per-band audio levels from PCM, and the plug-in
/// protocol a playback engine uses to hand PCM to analyzers like it. No
/// dependencies beyond Apple's Accelerate, AVFoundation and SwiftUI, and nothing
/// radio- or ShoutKit-specific, so any `AVAudioEngine` app can adopt it.
///
/// Two products, so an app that draws its own meter never links SwiftUI code it
/// doesn't use: `AudioLevels` (analysis and taps) and `AudioLevelsUI` (a
/// themeable bars view). The algorithm is specified, with golden vectors, in
/// docs/audio-levels-spec.md; the Android client implements the same spec.
let package = Package(
    name: "AudioLevels",
    platforms: [
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26),
        .macOS(.v15),
    ],
    products: [
        .library(name: "AudioLevels", targets: ["AudioLevels"]),
        .library(name: "AudioLevelsUI", targets: ["AudioLevelsUI"]),
    ],
    targets: [
        .target(name: "AudioLevels", swiftSettings: [optimizeForSize]),
        .target(
            name: "AudioLevelsUI",
            dependencies: ["AudioLevels"],
            swiftSettings: [optimizeForSize, .defaultIsolation(MainActor.self)],
        ),
        .testTarget(
            name: "AudioLevelsTests",
            dependencies: ["AudioLevels"],
            resources: [.copy("Resources/golden-vectors.json")],
        ),
    ],
)
