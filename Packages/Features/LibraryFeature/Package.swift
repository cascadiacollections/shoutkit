// swift-tools-version: 6.4

import PackageDescription

/// Release builds of this package optimize for size, not speed (DECISIONS.md,
/// 2026-11-07). A project-level `SWIFT_OPTIMIZATION_LEVEL` never reaches package
/// targets, so this is the only place it can be set. `unsafeFlags` is allowed
/// because the package is only ever consumed by path from this repository.
let optimizeForSize: SwiftSetting = .unsafeFlags(["-Osize"], .when(configuration: .release))

let package = Package(
    name: "LibraryFeature",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(name: "LibraryFeature", targets: ["LibraryFeature"]),
    ],
    dependencies: [
        .package(path: "../../DesignSystem"),
        .package(path: "../../LibraryFeatureCore"),
        .package(path: "../../Playback"),
        .package(path: "../../Persistence"),
        .package(path: "../../RadioDirectory"),
    ],
    targets: [
        .target(
            name: "LibraryFeature",
            dependencies: [
                "DesignSystem",
                "LibraryFeatureCore",
                "Playback",
                "Persistence",
                "RadioDirectory",
            ],
            resources: [.process("Resources/Localizable.xcstrings")],
            swiftSettings: [optimizeForSize, .defaultIsolation(MainActor.self)],
        ),
    ],
)
