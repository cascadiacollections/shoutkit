// swift-tools-version: 6.4

import PackageDescription

// App-side debug tooling. This package exists so Pulse never appears in the
// dependency graph of the reusable packages (RadioDirectory et al.) — only the
// app target links it.
//
// The product is `.dynamic`, and that is what keeps Pulse out of Release
// (DECISIONS.md, 2026-11-07). Xcode links static package code as prelinked
// object files, and Pulse's ObjC classes are dead-strip roots, so as a static
// product ~715 KB of Pulse shipped in every Release binary even with every
// reference `#if DEBUG`. As a framework, Release references nothing in it, the
// linker drops the load command (`-dead_strip_dylibs`), and
// `EXCLUDED_SOURCE_FILE_NAMES` keeps the app's "Embed Frameworks" phase from
// copying it (both in Config/Release.xcconfig). CI checks both halves.
//
// It depends on Foundation and Pulse only — deliberately not on RadioDirectory.
// A dynamic framework statically links its dependencies, so depending on a
// package the app also links would put a second copy of it in the process,
// and installing a session into the framework's copy of
// `URLSessionHTTPTransport` would silently do nothing for the app's.
let package = Package(
    name: "DebugSupport",
    platforms: [
        .iOS(.v26),
        .macOS(.v13),
    ],
    products: [
        .library(name: "DebugSupport", type: .dynamic, targets: ["DebugSupport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/kean/Pulse.git", exact: "5.2.3"),
    ],
    targets: [
        .target(
            name: "DebugSupport",
            dependencies: [
                .product(name: "Pulse", package: "Pulse"),
            ],
        ),
    ],
)
