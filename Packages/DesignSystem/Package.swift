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
        .package(path: "../ImageIODownsample"),
        .package(path: "../RadioDirectory"),
        .package(path: "../Playback"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.6.0")
    ],
    targets: [
        .target(
            name: "DesignSystem",
            dependencies: [
                "RadioDirectory",
                "Playback",
                "ImageIODownsample",
                .product(name: "OrderedCollections", package: "swift-collections")
            ],
            resources: [.process("Resources/Localizable.xcstrings")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"]
        )
    ]
)
