// swift-tools-version: 6.4

import PackageDescription

/// Release builds of this package optimize for size, not speed (DECISIONS.md,
/// 2026-11-07). A project-level `SWIFT_OPTIMIZATION_LEVEL` never reaches package
/// targets, so this is the only place it can be set. `unsafeFlags` is allowed
/// because the package is only ever consumed by path from this repository.
let optimizeForSize: SwiftSetting = .unsafeFlags(["-Osize"], .when(configuration: .release))

// The platform-free half of SettingsFeature, following the PlayerFeatureCore
// pattern: `SettingsFeature` depends on DesignSystem, which declares
// `.iOS(.v26)` alone and so doesn't build for the mac host, meaning nothing in
// that package could ever be reached by `swift test` — and it had no tests.
//
// It depends on `Playback` only for `EqualizerPreset`, which is a plain
// `Int`-backed enum with no platform audio dependency; `Playback` is itself a
// host-testable package, so the dependency doesn't cost the host loop.
let package = Package(
    name: "SettingsFeatureCore",
    platforms: [
        .iOS(.v26),
        // Declared so the suite can run on the mac host (`swift test`), same
        // pattern as BrowseFeatureCore/SearchFeatureCore/PlayerFeatureCore.
        .macOS(.v15),
    ],
    products: [
        .library(name: "SettingsFeatureCore", targets: ["SettingsFeatureCore"]),
    ],
    dependencies: [
        .package(path: "../Playback"),
    ],
    targets: [
        // No `.defaultIsolation(MainActor.self)`, like PlayerFeatureCore: pure
        // value-in/value-out with no observable state and no UI work.
        .target(
            name: "SettingsFeatureCore",
            dependencies: ["Playback"],
            swiftSettings: [optimizeForSize],
        ),
        .testTarget(
            name: "SettingsFeatureCoreTests",
            dependencies: ["SettingsFeatureCore"],
        ),
    ],
)
