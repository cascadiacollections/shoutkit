// swift-tools-version: 6.4

import PackageDescription

// The AudioStreaming-backed `RadioPlaybackEngine`, split out of `Playback` so
// that package carries no codec dependency (see #122).
//
// AudioStreaming pulls two remote `binaryTarget` packages — the ogg and vorbis
// xcframeworks — and SwiftPM enumerates binary artifacts with no platform
// filtering, so a `condition: .when(platforms: [.iOS])` on the target dependency
// stopped them being *linked* on the mac host but never stopped them being
// *fetched* (DECISIONS.md 2026-08-05). Every `swift test` in `Packages/Playback`
// downloaded ~5.6 MB of codec zips for a suite that links neither, and any
// external adopter of the MIT-licensed `Playback` inherited the whole C codec
// stack.
//
// Expressing the boundary as a separate package the *app target alone links* is
// what fixes both, and it is harder to undo by accident than a target-dependency
// condition. Same shape as `Packages/DebugSupport`, which keeps Pulse out of the
// reusable packages.
//
// The platform list is load-bearing, not stylistic (#123), and the omission of
// `.watchOS` is the load-bearing part. The ogg and vorbis xcframeworks ship no
// watchOS slice, so adding `.watchOS` here — or letting the watch app link this
// product — breaks the watch build at link time with an error that names a
// missing architecture rather than the real cause. The watch supplies its own
// `AVPlayer`-backed `WatchRadioPlaybackEngine` and must keep doing so.
//
// `.tvOS` is here because the whole chain genuinely supports it, checked at the
// exact tags in `Package.resolved` rather than taken from the manifests: both
// xcframeworks carry real `tvos-arm64` and `tvos-arm64_x86_64-simulator` slices,
// and AudioStreaming 1.4.4 declares `.tvOS(.v16)`. That is the difference from
// watchOS, and it is why `ShoutKitTVApp` can link this product and drop its own
// AVPlayer engine (DECISIONS.md 2026-08-12).
let package = Package(
    name: "PlaybackEngineAudioStreaming",
    platforms: [
        .iOS(.v26),
        .tvOS(.v26)
    ],
    products: [
        .library(name: "PlaybackEngineAudioStreaming", targets: ["PlaybackEngineAudioStreaming"])
    ],
    dependencies: [
        .package(path: "../Playback"),
        // Declared, not inherited through Playback: `registerProductionPlaybackEngine()`
        // imports FactoryKit directly to register over the container's stub
        // default, and a target may only import modules its own manifest names.
        // Kept `exact` at the same version as every other manifest — the
        // dependabot `factory` group spans all of them for that reason, and this
        // directory is in its list.
        .package(url: "https://github.com/hmlongco/Factory.git", exact: "3.3.2"),
        .package(url: "https://github.com/dimitris-c/AudioStreaming.git", exact: "1.4.4")
    ],
    targets: [
        .target(
            name: "PlaybackEngineAudioStreaming",
            dependencies: [
                "Playback",
                .product(name: "FactoryKit", package: "Factory"),
                .product(name: "AudioStreaming", package: "AudioStreaming")
            ]
        )
    ]
)
