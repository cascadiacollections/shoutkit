// swift-tools-version: 6.4

import PackageDescription

/// Release builds of this package optimize for size, not speed (DECISIONS.md,
/// 2026-11-07). A project-level `SWIFT_OPTIMIZATION_LEVEL` never reaches package
/// targets, so this is the only place it can be set. `unsafeFlags` is allowed
/// because the package is only ever consumed by path from this repository.
let optimizeForSize: SwiftSetting = .unsafeFlags(["-Osize"], .when(configuration: .release))

let package = Package(
    name: "SettingsFeature",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
    ],
    dependencies: [
        .package(path: "../../DesignSystem"),
        .package(path: "../../SettingsFeatureCore"),
        .package(path: "../../Persistence"),
        .package(path: "../../FeatureFlags"),
        .package(path: "../../Playback"),
    ],
    targets: [
        .target(
            name: "SettingsFeature",
            dependencies: [
                "DesignSystem",
                "SettingsFeatureCore",
                "Persistence",
                "FeatureFlags",
                "Playback",
            ],
            resources: [
                .copy("Resources/apache-2.0.txt"),
                .copy("Resources/audiostreaming-mit.txt"),
                .copy("Resources/factory-mit.txt"),
                .copy("Resources/gpl-3.0.txt"),
                .copy("Resources/mit.txt"),
                .copy("Resources/ogg-bsd.txt"),
                .copy("Resources/pulse-mit.txt"),
                .copy("Resources/vorbis-bsd.txt"),
                .process("Resources/Localizable.xcstrings"),
            ],
            swiftSettings: [optimizeForSize, .defaultIsolation(MainActor.self)],
        ),
    ],
)
