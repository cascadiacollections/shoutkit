// swift-tools-version: 6.4

import PackageDescription

/// Release builds of this package optimize for size, not speed (DECISIONS.md,
/// 2026-11-07). A project-level `SWIFT_OPTIMIZATION_LEVEL` never reaches package
/// targets, so this is the only place it can be set. `unsafeFlags` is allowed
/// because the package is only ever consumed by path from this repository.
let optimizeForSize: SwiftSetting = .unsafeFlags(["-Osize"], .when(configuration: .release))

let package = Package(
    name: "BrowseFeatureCore",
    platforms: [
        .iOS(.v26),
        // Declared so the view-model test suite can run on the mac host
        // (`swift test`), same pattern as RadioDirectory/Playback/Persistence.
        .macOS(.v15),
    ],
    products: [
        .library(name: "BrowseFeatureCore", targets: ["BrowseFeatureCore"]),
    ],
    dependencies: [
        .package(path: "../RadioDirectory"),
        .package(url: "https://github.com/hmlongco/Factory.git", exact: "3.5.2"),
    ],
    targets: [
        .target(
            name: "BrowseFeatureCore",
            dependencies: [
                "RadioDirectory",
                .product(name: "FactoryKit", package: "Factory"),
            ],
            swiftSettings: [optimizeForSize, .defaultIsolation(MainActor.self)],
        ),
        .testTarget(
            name: "BrowseFeatureCoreTests",
            dependencies: ["BrowseFeatureCore"],
        ),
    ],
)
