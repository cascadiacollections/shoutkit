// swift-tools-version: 6.4

import PackageDescription

/// Release builds of this package optimize for size, not speed (DECISIONS.md,
/// 2026-11-07). A project-level `SWIFT_OPTIMIZATION_LEVEL` never reaches package
/// targets, so this is the only place it can be set. `unsafeFlags` is allowed
/// because the package is only ever consumed by path from this repository.
let optimizeForSize: SwiftSetting = .unsafeFlags(["-Osize"], .when(configuration: .release))

let package = Package(
    name: "ImageIODownsample",
    platforms: [
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .macOS(.v15),
    ],
    products: [
        .library(name: "ImageIODownsample", targets: ["ImageIODownsample"]),
    ],
    targets: [
        .target(name: "ImageIODownsample", swiftSettings: [optimizeForSize]),
        .testTarget(
            name: "ImageIODownsampleTests",
            dependencies: ["ImageIODownsample"],
        ),
    ],
)
