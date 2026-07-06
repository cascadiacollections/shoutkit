// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DesignSystem",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"])
    ],
    dependencies: [
        .package(path: "../RadioDirectory"),
        .package(path: "../Playback")
    ],
    targets: [
        .target(
            name: "DesignSystem",
            dependencies: ["RadioDirectory", "Playback"],
            resources: [.process("Resources/Localizable.xcstrings")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        )
    ]
)
