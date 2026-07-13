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
                .copy("Resources/apache-2.0.txt"),
                .copy("Resources/audiostreaming-mit.txt"),
                .copy("Resources/factory-mit.txt"),
                .copy("Resources/gpl-3.0.txt"),
                .copy("Resources/mit.txt"),
                .copy("Resources/ogg-bsd.txt"),
                .copy("Resources/vorbis-bsd.txt"),
                .process("Resources/Localizable.xcstrings")
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        )
    ]
)
