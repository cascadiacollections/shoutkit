// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "Playback",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .watchOS(.v26),
        // Declared so the controller/state-machine test suite can run on the mac
        // host (`swift test`); the AVPlayer/UIKit-backed production types are
        // gated behind canImport(UIKit) and the app product remains iOS-only.
        .macOS(.v15)
    ],
    products: [
        .library(name: "Playback", targets: ["Playback"])
    ],
    // No AudioStreaming here, deliberately. The concrete engine lives in
    // Packages/PlaybackEngineAudioStreaming, which only the iOS app target
    // links; this package keeps the `RadioPlaybackEngine` seam and nothing that
    // implements it against a codec (#122).
    //
    // The previous arrangement declared AudioStreaming here with
    // `condition: .when(platforms: [.iOS])` on the target dependency, and a
    // comment claiming the mac host job therefore "never has to fetch or link
    // it." *Link* was right; *fetch* was not. A platform condition applies to a
    // target dependency — `.package(url:)` takes no condition, SwiftPM has no
    // such API — so the repo was cloned and its manifest read unconditionally,
    // and binary artifacts are then enumerated with no platform filtering at
    // all. Every `swift test` here downloaded the ogg and vorbis xcframeworks
    // (~5.6 MB zipped) to run a suite that links neither; the cold CI run on
    // PR #127 logged exactly that. See DECISIONS.md 2026-08-05 and issue #126.
    dependencies: [
        .package(path: "../ImageIODownsample"),
        .package(path: "../RadioDirectory"),
        .package(url: "https://github.com/hmlongco/Factory.git", exact: "3.3.2")
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
