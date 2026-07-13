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
        .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.2.1"),
        .package(url: "https://github.com/hmlongco/Factory.git", exact: "3.3.1"),
        .package(url: "https://github.com/kean/Pulse.git", exact: "5.2.3")
    ],
    targets: [
        .target(
            name: "RadioDirectory",
            dependencies: [
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "FactoryKit", package: "Factory"),
                .product(name: "Pulse", package: "Pulse", condition: .when(configuration: .debug))
            ],
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .testTarget(
            name: "RadioDirectoryTests",
            dependencies: ["RadioDirectory"]
        )
    ]
)
