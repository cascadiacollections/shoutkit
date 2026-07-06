// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SearchFeature",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "SearchFeature", targets: ["SearchFeature"])
    ],
    dependencies: [
        .package(path: "../../DesignSystem"),
        .package(path: "../../Playback"),
        .package(path: "../../Persistence"),
        .package(path: "../../RadioDirectory")
    ],
    targets: [
        .target(
            name: "SearchFeature",
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
