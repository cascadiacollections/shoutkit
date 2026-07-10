// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RadioDirectory",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v13)
    ],
    products: [
        .library(name: "RadioDirectory", targets: ["RadioDirectory"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.2.1")
    ],
    targets: [
        .target(
            name: "RadioDirectory",
            dependencies: [
                .product(name: "Algorithms", package: "swift-algorithms")
            ],
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .testTarget(
            name: "RadioDirectoryTests",
            dependencies: ["RadioDirectory"]
        )
    ]
)
