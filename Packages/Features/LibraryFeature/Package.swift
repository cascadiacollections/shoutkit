// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "LibraryFeature",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v27)
    ],
    products: [
        .library(name: "LibraryFeature", targets: ["LibraryFeature"])
    ],
    dependencies: [
        .package(path: "../../DesignSystem"),
        .package(path: "../../Playback"),
        .package(path: "../../Persistence"),
        .package(path: "../../RadioDirectory")
    ],
    targets: [
        .target(
            name: "LibraryFeature",
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
