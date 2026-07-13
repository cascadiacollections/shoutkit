// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Playback",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        // Declared so the controller/state-machine test suite can run on the mac
        // host (`swift test`); the AVPlayer/UIKit-backed production types are
        // gated behind canImport(UIKit) and the app product remains iOS-only.
        .macOS(.v15)
    ],
    products: [
        .library(name: "Playback", targets: ["Playback"])
    ],
    dependencies: [
        .package(path: "../ImageIODownsample"),
        .package(path: "../RadioDirectory"),
        .package(url: "https://github.com/hmlongco/Factory.git", exact: "3.3.1")
    ],
    targets: [
        .target(
            name: "Playback",
            dependencies: [
                "ImageIODownsample",
                "RadioDirectory",
                .product(name: "FactoryKit", package: "Factory")
            ],
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .testTarget(
            name: "PlaybackTests",
            dependencies: ["Playback"]
        )
    ]
)
