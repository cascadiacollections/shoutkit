// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "Persistence",
    platforms: [
        .iOS(.v27),
        // Declared so the pure-SwiftData test suite can run on the mac host
        // (`swift test`); the app product itself remains iOS-only.
        .macOS(.v15)
    ],
    products: [
        .library(name: "Persistence", targets: ["Persistence"])
    ],
    dependencies: [
        .package(path: "../RadioDirectory"),
        .package(path: "../FeatureFlags"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
        .package(url: "https://github.com/hmlongco/Factory.git", from: "3.3.1")
    ],
    targets: [
        .target(
            name: "Persistence",
            dependencies: [
                "RadioDirectory",
                "FeatureFlags",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "FactoryKit", package: "Factory")
            ]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence"]
        )
    ]
)
