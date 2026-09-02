// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ShoutKitRustSpike",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "RustSpike", targets: ["RustSpike"])
    ],
    targets: [
        // Built by ../build.sh from the Rust crate; not checked in.
        .binaryTarget(
            name: "RustSpikeFFI",
            path: "artifacts/ShoutKitRustSpike.xcframework"
        ),
        .target(
            name: "RustSpike",
            dependencies: ["RustSpikeFFI"]
        ),
        .testTarget(
            name: "RustSpikeTests",
            dependencies: ["RustSpike"]
        )
    ]
)
