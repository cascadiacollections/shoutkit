// swift-tools-version: 6.4

import PackageDescription

// The platform-free half of PlayerFeature, following the BrowseFeatureCore /
// SearchFeatureCore pattern: `PlayerFeature` depends on DesignSystem, whose
// UIKit-only sources don't build for the mac host at all, so nothing in that
// package could ever be reached by `swift test` — and it had no tests.
//
// Deliberately small. It holds the decisions a player surface makes, not the
// surfaces themselves, and takes plain values rather than the app's observable
// types so a test needs no SwiftData container and no PlaybackController.
let package = Package(
    name: "PlayerFeatureCore",
    platforms: [
        .iOS(.v27),
        // Declared so the suite can run on the mac host (`swift test`), same
        // pattern as BrowseFeatureCore/SearchFeatureCore.
        .macOS(.v15)
    ],
    products: [
        .library(name: "PlayerFeatureCore", targets: ["PlayerFeatureCore"])
    ],
    targets: [
        // No `.defaultIsolation(MainActor.self)` here, unlike the other two
        // Core packages: those hold `@Observable` view models that belong on the
        // main actor, whereas this is pure value-in/value-out and has no reason
        // to be isolated to anything.
        .target(name: "PlayerFeatureCore"),
        .testTarget(
            name: "PlayerFeatureCoreTests",
            dependencies: ["PlayerFeatureCore"]
        )
    ]
)
