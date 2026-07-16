// swift-tools-version: 6.4

import PackageDescription

// App-side debug tooling. This package exists so Pulse never appears in the
// dependency graph of the reusable packages (RadioDirectory et al.) — only the
// app target links it, and every Pulse reference is #if DEBUG (CI symbol-checks
// the Release binary to prove it never ships).
let package = Package(
    name: "DebugSupport",
    platforms: [
        .iOS(.v27),
        .macOS(.v13)
    ],
    products: [
        .library(name: "DebugSupport", targets: ["DebugSupport"])
    ],
    dependencies: [
        .package(path: "../RadioDirectory"),
        .package(url: "https://github.com/kean/Pulse.git", exact: "5.2.3")
    ],
    targets: [
        .target(
            name: "DebugSupport",
            dependencies: [
                "RadioDirectory",
                .product(name: "Pulse", package: "Pulse")
            ]
        )
    ]
)
