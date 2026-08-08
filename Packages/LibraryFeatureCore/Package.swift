// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "LibraryFeatureCore",
    platforms: [
        .iOS(.v27),
        .macOS(.v15)
    ],
    products: [
        .library(name: "LibraryFeatureCore", targets: ["LibraryFeatureCore"])
    ],
    targets: [
        .target(name: "LibraryFeatureCore"),
        .testTarget(
            name: "LibraryFeatureCoreTests",
            dependencies: ["LibraryFeatureCore"]
        )
    ]
)
