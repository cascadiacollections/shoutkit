// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "ImageIODownsample",
    platforms: [
        .iOS(.v27),
        .watchOS(.v27),
        .macOS(.v15)
    ],
    products: [
        .library(name: "ImageIODownsample", targets: ["ImageIODownsample"])
    ],
    targets: [
        .target(name: "ImageIODownsample"),
        .testTarget(
            name: "ImageIODownsampleTests",
            dependencies: ["ImageIODownsample"]
        )
    ]
)
