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
    // No image-loading library here. The app's Nuke pipeline lives in the
    // app-side `ArtworkPipelineNuke` package and is registered through
    // `ArtworkImageSource.register(_:)` (DECISIONS.md, 2026-11-28), so this
    // MIT package stays adoptable without Nuke.
    dependencies: [
        .package(path: "../ImageIODownsample"),
        .package(path: "../RadioDirectory"),
        .package(path: "../Playback"),
    ],
    targets: [
        .target(
            name: "DesignSystem",
            dependencies: [
                "RadioDirectory",
                "Playback",
                "ImageIODownsample",
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
