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
    targets: [
        .target(
            name: "RadioDirectory",
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .testTarget(
            name: "RadioDirectoryTests",
            dependencies: ["RadioDirectory"]
        )
    ]
)
