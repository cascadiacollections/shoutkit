// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SettingsFeature",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "SettingsFeature", targets: ["SettingsFeature"])
    ],
    dependencies: [
        .package(path: "../../DesignSystem"),
        .package(path: "../../Persistence")
    ],
    targets: [
        .target(
            name: "SettingsFeature",
            dependencies: [
                "DesignSystem",
                "Persistence"
            ],
            resources: [
                .copy("Resources/gpl-3.0.txt"),
                .copy("Resources/mit.txt"),
                .process("Resources/Localizable.xcstrings")
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        )
    ]
)
