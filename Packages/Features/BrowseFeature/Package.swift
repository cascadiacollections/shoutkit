// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "BrowseFeature",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "BrowseFeature", targets: ["BrowseFeature"])
    ],
    dependencies: [
        .package(path: "../../DesignSystem"),
        .package(path: "../../Playback"),
        .package(path: "../../Persistence"),
        .package(path: "../../RadioDirectory"),
        .package(url: "https://github.com/hmlongco/Factory.git", exact: "3.3.1")
    ],
    targets: [
        .target(
            name: "BrowseFeature",
            dependencies: [
                "DesignSystem",
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
