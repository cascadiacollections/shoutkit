// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Persistence",
    platforms: [
        .iOS(.v26),
        // Declared so the pure-SwiftData test suite can run on the mac host
        // (`swift test`); the app product itself remains iOS-only.
        .macOS(.v15)
    ],
    products: [
        .library(name: "Persistence", targets: ["Persistence"])
    ],
    dependencies: [
        .package(path: "../RadioDirectory")
    ],
    targets: [
        .target(
            name: "Persistence",
            dependencies: ["RadioDirectory"]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence"]
        )
    ]
)
