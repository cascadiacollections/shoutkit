// swift-tools-version: 6.4

import PackageDescription

/// Release builds of this package optimize for size, not speed (DECISIONS.md,
/// 2026-11-07). A project-level `SWIFT_OPTIMIZATION_LEVEL` never reaches package
/// targets, so this is the only place it can be set. `unsafeFlags` is allowed
/// because the package is only ever consumed by path from this repository.
let optimizeForSize: SwiftSetting = .unsafeFlags(["-Osize"], .when(configuration: .release))

let package = Package(
    name: "DesignSystem",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    dependencies: [
        .package(path: "../ImageIODownsample"),
        .package(path: "../RadioDirectory"),
        .package(path: "../Playback"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.7.5"),
    ],
    targets: [
        .target(
            name: "DesignSystem",
            dependencies: [
                "RadioDirectory",
                "Playback",
                "ImageIODownsample",
                .product(name: "OrderedCollections", package: "swift-collections"),
            ],
            resources: [.process("Resources/Localizable.xcstrings")],
            swiftSettings: [optimizeForSize, .defaultIsolation(MainActor.self)],
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"],
        ),
    ],
)
