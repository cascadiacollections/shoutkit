// swift-tools-version: 6.2

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
        .package(path: "../../DesignSystem"),
        .package(path: "../../Playback"),
        .package(path: "../../Persistence"),
        .package(path: "../../RadioDirectory")
    ],
    targets: [
        .target(
            name: "BrowseFeature",
            dependencies: [
                "DesignSystem",
                "Playback",
                "Persistence",
                "RadioDirectory"
            ],
            resources: [.process("Resources/Localizable.xcstrings")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        )
    ]
)
