// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "BrowseFeatureCore",
    platforms: [
        .iOS(.v26),
        // Declared so the view-model test suite can run on the mac host
        // (`swift test`), same pattern as RadioDirectory/Playback/Persistence.
        .macOS(.v15)
    ],
    products: [
        .library(name: "BrowseFeatureCore", targets: ["BrowseFeatureCore"])
    ],
    dependencies: [
        .package(path: "../RadioDirectory"),
        .package(url: "https://github.com/hmlongco/Factory.git", exact: "3.3.2")
    ],
    targets: [
        .target(
            name: "BrowseFeatureCore",
            dependencies: [
                "RadioDirectory",
                .product(name: "FactoryKit", package: "Factory")
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "BrowseFeatureCoreTests",
            dependencies: ["BrowseFeatureCore"]
        )
    ]
)
