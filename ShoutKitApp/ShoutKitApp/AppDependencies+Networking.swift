import DebugSupport
import Foundation
import RadioDirectory

// The process-wide networking install `bootstrap()` performs before anything
// else in the graph exists: shared URL cache sizing, Debug-only Pulse proxying,
// and the latency-tuned shared session. Split out of AppDependencies.swift for
// the 400-line `file_length` limit CI enforces via `swiftlint --strict`, the
// same remedy as the AudioStreamingPlaybackEngine+Session split.

extension AppDependencies {
    /// Debug-only Pulse proxying, the latency-tuned shared session, and the
    /// shared URL cache sizing. Must run before anything issues a network
    /// request, since the first touch of `URLSessionHTTPTransport.shared`
    /// locks the session in (first-write-wins, so in Debug the Pulse session
    /// installed first holds the slot — it's built from the same tuned
    /// configuration, so behaviour matches Release either way).
    static func installSharedNetworking() {
        // Size the shared URL cache for RAM-constrained devices: raw bytes
        // (artwork, directory JSON) belong on disk — cheap, and they survive
        // relaunch — while the in-memory tier stays small; decoded bitmaps
        // have their own bounded caches in DesignSystem. Must be set before
        // any URLSessionConfiguration below is *created*: a configuration
        // captures the URLCache.shared reference at creation time, so setting
        // the tuned cache afterwards would leave the shared transport (which
        // carries all directory and artwork traffic) on the old default cache.
        URLCache.shared = URLCache(
            memoryCapacity: 2 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024
        )

        DebugNetworkInspection.install()

        #if !DEBUG
        // Fail-fast when offline, responsive-data service type. In Debug,
        // DebugNetworkInspection.install() above already claimed the slot
        // with the same tuned configuration plus Pulse's proxy delegate.
        URLSessionHTTPTransport.installSharedSession(
            URLSession(configuration: URLSessionHTTPTransport.interactiveConfiguration())
        )
        #endif
    }
}
