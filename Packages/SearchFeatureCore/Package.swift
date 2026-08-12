// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SearchFeatureCore",
    platforms: [
        .iOS(.v26),
        // Declared so the view-model test suite can run on the mac host
        // (`swift test`), same pattern as RadioDirectory/Playback/Persistence.
        .macOS(.v15)
    ],
    products: [
        .library(name: "SearchFeatureCore", targets: ["SearchFeatureCore"])
    ],
    dependencies: [
        .package(path: "../RadioDirectory"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.1.5"),
        .package(url: "https://github.com/hmlongco/Factory.git", exact: "3.3.2")
    ],
    targets: [
        .target(
            name: "SearchFeatureCore",
            dependencies: [
                "RadioDirectory",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "FactoryKit", package: "Factory")
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "SearchFeatureCoreTests",
            dependencies: ["SearchFeatureCore"]
        )
    ]
)
