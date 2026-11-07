// swift-tools-version: 6.4

import PackageDescription

/// Release builds of this package optimize for size, not speed (DECISIONS.md,
/// 2026-11-07). A project-level `SWIFT_OPTIMIZATION_LEVEL` never reaches package
/// targets, so this is the only place it can be set. `unsafeFlags` is allowed
/// because the package is only ever consumed by path from this repository.
let optimizeForSize: SwiftSetting = .unsafeFlags(["-Osize"], .when(configuration: .release))

// The platform-free half of LibraryFeature, following the PlayerFeatureCore
// pattern: `LibraryFeature` depends on DesignSystem, which declares
// `.iOS(.v26)` alone and so doesn't build for the mac host, meaning nothing in
// that package could ever be reached by `swift test` — and it had no tests.
//
// It takes plain station-ID arrays rather than the SwiftData models the view
// queries, so a test needs no ModelContainer.
let package = Package(
    name: "LibraryFeatureCore",
    platforms: [
        .iOS(.v26),
        // Declared so the suite can run on the mac host (`swift test`), same
        // pattern as BrowseFeatureCore/SearchFeatureCore/PlayerFeatureCore.
        .macOS(.v15),
    ],
    products: [
        .library(name: "LibraryFeatureCore", targets: ["LibraryFeatureCore"]),
    ],
    targets: [
        // No `.defaultIsolation(MainActor.self)`, like PlayerFeatureCore: pure
        // value-in/value-out with no observable state and no UI work.
        .target(name: "LibraryFeatureCore", swiftSettings: [optimizeForSize]),
        .testTarget(
            name: "LibraryFeatureCoreTests",
            dependencies: ["LibraryFeatureCore"],
        ),
    ],
)
