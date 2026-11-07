// swift-tools-version: 6.4

import PackageDescription

/// Release builds of this package optimize for size, not speed (DECISIONS.md,
/// 2026-11-07). A project-level `SWIFT_OPTIMIZATION_LEVEL` never reaches package
/// targets, so this is the only place it can be set. `unsafeFlags` is allowed
/// because the package is only ever consumed by path from this repository.
let optimizeForSize: SwiftSetting = .unsafeFlags(["-Osize"], .when(configuration: .release))

let package = Package(
    name: "RadioDirectory",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .macOS(.v13),
    ],
    products: [
        .library(name: "RadioDirectory", targets: ["RadioDirectory"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hmlongco/Factory.git", exact: "3.5.2"),
    ],
    targets: [
        .target(
            name: "RadioDirectory",
            dependencies: [
                .product(name: "FactoryKit", package: "Factory"),
            ],
            resources: [.process("Resources/Localizable.xcstrings")],
            swiftSettings: [optimizeForSize],
        ),
        .testTarget(
            name: "RadioDirectoryTests",
            dependencies: ["RadioDirectory"],
        ),
    ],
)
