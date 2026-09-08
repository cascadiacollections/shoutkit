// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "PlayerFeature",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "PlayerFeature", targets: ["PlayerFeature"])
    ],
    dependencies: [
        .package(path: "../../DesignSystem"),
        .package(path: "../../Playback"),
        .package(path: "../../Persistence"),
        .package(path: "../../PlayerFeatureCore"),
        .package(path: "../../RadioDirectory")
    ],
    targets: [
        .target(
            name: "PlayerFeature",
            dependencies: [
                "DesignSystem",
                "Playback",
                "Persistence",
                "PlayerFeatureCore",
                "RadioDirectory"
            ],
            resources: [.process("Resources/Localizable.xcstrings")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        )
    ]
)
