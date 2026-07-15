// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FeatureFlags",
    platforms: [
        .iOS(.v26),
        .macOS(.v15)
    ],
    products: [
        .library(name: "FeatureFlags", targets: ["FeatureFlags"])
    ],
    dependencies: [
        .package(url: "https://github.com/hmlongco/Factory.git", exact: "3.3.1")
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
