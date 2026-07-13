// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Persistence",
    platforms: [
        // SwiftData (@Model, ModelContainer) and the Observation framework
        // (@Observable) require iOS 17. UserDefaults-backed fallback for iOS 16
        // is tracked as a follow-up; add #available guards here as that work lands.
        .iOS(.v17),
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
