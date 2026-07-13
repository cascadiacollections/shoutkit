// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SearchFeature",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "SearchFeature", targets: ["SearchFeature"])
    ],
    dependencies: [
        .package(path: "../../DesignSystem"),
        .package(path: "../../Playback"),
        .package(path: "../../Persistence"),
        .package(path: "../../RadioDirectory"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.1.5"),
        .package(url: "https://github.com/hmlongco/Factory.git", exact: "3.3.1")
    ],
    targets: [
        .target(
            name: "SearchFeature",
            dependencies: [
                "DesignSystem",
                "Playback",
                "Persistence",
                "RadioDirectory",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "FactoryKit", package: "Factory")
            ],
            resources: [.process("Resources/Localizable.xcstrings")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        )
    ]
)
