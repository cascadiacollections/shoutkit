// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SettingsFeatureCore",
    platforms: [
        .iOS(.v27),
        .macOS(.v15)
    ],
    products: [
        .library(name: "SettingsFeatureCore", targets: ["SettingsFeatureCore"])
    ],
    targets: [
        .target(name: "SettingsFeatureCore"),
        .testTarget(
            name: "SettingsFeatureCoreTests",
            dependencies: ["SettingsFeatureCore"]
        )
    ]
)
