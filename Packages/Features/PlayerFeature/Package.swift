// swift-tools-version: 6.4

import PackageDescription

/// Release builds of this package optimize for size, not speed (DECISIONS.md,
/// 2026-11-07). A project-level `SWIFT_OPTIMIZATION_LEVEL` never reaches package
/// targets, so this is the only place it can be set. `unsafeFlags` is allowed
/// because the package is only ever consumed by path from this repository.
let optimizeForSize: SwiftSetting = .unsafeFlags(["-Osize"], .when(configuration: .release))

let package = Package(
    name: "PlayerFeature",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(name: "PlayerFeature", targets: ["PlayerFeature"]),
    ],
    dependencies: [
        .package(path: "../../AudioLevels"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../Playback"),
        .package(path: "../../Persistence"),
        .package(path: "../../PlayerFeatureCore"),
        .package(path: "../../RadioDirectory"),
    ],
    targets: [
        .target(
            name: "PlayerFeature",
            dependencies: [
                .product(name: "AudioLevels", package: "AudioLevels"),
                .product(name: "AudioLevelsUI", package: "AudioLevels"),
                "DesignSystem",
                "Playback",
                "Persistence",
                "PlayerFeatureCore",
                "RadioDirectory",
            ],
            resources: [.process("Resources/Localizable.xcstrings")],
            swiftSettings: [optimizeForSize, .defaultIsolation(MainActor.self)],
        ),
    ],
)
