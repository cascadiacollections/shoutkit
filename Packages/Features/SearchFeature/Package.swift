// swift-tools-version: 6.4

import PackageDescription

/// Release builds of this package optimize for size, not speed (DECISIONS.md,
/// 2026-11-07). A project-level `SWIFT_OPTIMIZATION_LEVEL` never reaches package
/// targets, so this is the only place it can be set. `unsafeFlags` is allowed
/// because the package is only ever consumed by path from this repository.
let optimizeForSize: SwiftSetting = .unsafeFlags(["-Osize"], .when(configuration: .release))

let package = Package(
    name: "SearchFeature",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(name: "SearchFeature", targets: ["SearchFeature"]),
    ],
    dependencies: [
        .package(path: "../../SearchFeatureCore"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../Playback"),
        .package(path: "../../Persistence"),
        .package(path: "../../RadioDirectory"),
        .package(url: "https://github.com/hmlongco/Factory.git", exact: "3.5.2"),
    ],
    targets: [
        .target(
            name: "SearchFeature",
            dependencies: [
                "SearchFeatureCore",
                "DesignSystem",
                "Playback",
                "Persistence",
                "RadioDirectory",
                .product(name: "FactoryKit", package: "Factory"),
            ],
            resources: [.process("Resources/Localizable.xcstrings")],
            swiftSettings: [optimizeForSize, .defaultIsolation(MainActor.self)],
        ),
    ],
)
