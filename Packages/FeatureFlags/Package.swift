// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "FeatureFlags",
    platforms: [
        .iOS(.v26),
        .watchOS(.v26),
        // Declared so the test suite can run on the mac host (`swift test`,
        // exercised by CI's host-tests job); the app product remains iOS-only.
        .macOS(.v15)
    ],
    products: [
        .library(name: "FeatureFlags", targets: ["FeatureFlags"])
    ],
    dependencies: [
        .package(url: "https://github.com/hmlongco/Factory.git", exact: "3.3.2")
    ],
    targets: [
        .target(
            name: "FeatureFlags",
            dependencies: [
                .product(name: "FactoryKit", package: "Factory")
            ]
        ),
        .testTarget(
            name: "FeatureFlagsTests",
            dependencies: ["FeatureFlags"]
        )
    ]
)
