// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "BrowseFeature",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "BrowseFeature", targets: ["BrowseFeature"])
    ],
    dependencies: [
        .package(path: "../../BrowseFeatureCore"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../FeatureFlags"),
        .package(path: "../../Playback"),
        .package(path: "../../Persistence"),
        .package(path: "../../RadioDirectory"),
        .package(url: "https://github.com/hmlongco/Factory.git", exact: "3.3.2")
    ],
    targets: [
        .target(
            name: "BrowseFeature",
            dependencies: [
                "BrowseFeatureCore",
                "DesignSystem",
                "FeatureFlags",
                "Playback",
                "Persistence",
                "RadioDirectory",
                .product(name: "FactoryKit", package: "Factory")
            ],
            resources: [.process("Resources/Localizable.xcstrings")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        )
    ]
)
