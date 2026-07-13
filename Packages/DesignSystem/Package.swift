// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DesignSystem",
    defaultLocalization: "en",
    platforms: [
        // DesignSystem imports Playback (iOS 17 minimum) for StationPlaybackPhase.
        // Move shared presentational types to a lower-level package to reach iOS 16.
        .iOS(.v17)
    ],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"])
    ],
    dependencies: [
        .package(path: "../ImageIODownsample"),
        .package(path: "../RadioDirectory"),
        .package(path: "../Playback"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.6.0")
    ],
    targets: [
        .target(
            name: "DesignSystem",
            dependencies: [
                "RadioDirectory",
                "Playback",
                "ImageIODownsample",
                .product(name: "OrderedCollections", package: "swift-collections")
            ],
            resources: [.process("Resources/Localizable.xcstrings")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"]
        )
    ]
)
