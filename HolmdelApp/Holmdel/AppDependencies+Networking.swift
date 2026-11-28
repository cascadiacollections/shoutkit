#if DEBUG
    // Debug-only: DebugSupport is a dynamic framework that Release strips from
    // the bundle, so nothing in Release may reference it (DECISIONS.md, 2026-11-07).
    import DebugSupport
#endif
import ArtworkPipelineNuke
import DesignSystem
import Foundation
import PlaybackEngineAudioStreaming
import RadioDirectory

// The process-wide installs `bootstrap()` performs before anything else in the
// graph exists: shared URL cache sizing, Debug-only Pulse proxying, the
// latency-tuned shared session, the production playback engine's Factory
// registration, and the artwork pipeline DesignSystem draws through. Split out
// of AppDependencies.swift for the 400-line `file_length` limit CI enforces via
// `swiftlint --strict`, the same remedy as the
// AudioStreamingPlaybackEngine+Session split.

extension AppDependencies {
    /// The registrations that must be in place before any of the graph is
    /// constructed. Grouped because they share that contract, not because they
    /// share a subject — and because `bootstrap()`'s body sits against the
    /// 50-line `function_body_length` limit, so each new process-wide install
    /// belongs here rather than as another line up there.
    static func installProcessWideServices() {
        installSharedNetworking()
        // Debug-only memory-headroom and thermal logging into Pulse. Before the
        // graph exists, so its launch sample is the baseline the graph's own
        // allocations are measured against.
        #if DEBUG
            DebugResourceMonitor.start()
        #endif
        // `PlaybackController`'s production init resolves its engine through
        // Factory, and `Playback` ships only the stub — the concrete engine
        // lives in the iOS-only PlaybackEngineAudioStreaming package (#122).
        // Miss this and the app builds, launches, and plays silence.
        registerProductionPlaybackEngine()
        registerProductionArtworkPipeline()
    }

    /// Hands DesignSystem's artwork surfaces the Nuke pipeline (memory and
    /// disk cache, coalescing, off-main thumbnail decode). DesignSystem is MIT
    /// and ships no image library, so the pipeline lives in the app-side
    /// `ArtworkPipelineNuke` package and is wired here, the same shape as the
    /// playback engine above. Miss this and artwork still loads, uncached.
    static func registerProductionArtworkPipeline() {
        ArtworkImageSource.register { request in
            await NukeArtworkPipeline.image(
                for: request.url,
                maxPixelSize: request.maxPixelSize,
                isPrefetch: request.isPrefetch,
                transport: request.transport,
            )
        }
    }

    /// Debug-only Pulse proxying, the latency-tuned shared session, and the
    /// shared URL cache sizing. Must run before anything issues a network
    /// request, since the first touch of `URLSessionHTTPTransport.shared`
    /// locks the session in (first-write-wins, so in Debug the Pulse session
    /// installed first holds the slot — it's built from the same tuned
    /// configuration, so behaviour matches Release either way).
    static func installSharedNetworking() {
        // Size the shared URL cache for RAM-constrained devices: raw bytes
        // (directory JSON, artwork) belong on disk — cheap, and they survive
        // relaunch — while the in-memory tier stays small. The in-app artwork
        // pipeline (ArtworkPipelineNuke) reads its own disk cache instead of
        // this one, but its responses are still written here, and the lock
        // screen's `nowPlayingArtwork` session reads them back with
        // `.returnCacheDataElseLoad`. Must be set before any
        // URLSessionConfiguration below is *created*: a configuration
        // captures the URLCache.shared reference at creation time, so setting
        // the tuned cache afterwards would leave the shared transport (which
        // carries all directory and artwork traffic) on the old default cache.
        URLCache.shared = URLCache(
            memoryCapacity: 2 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024,
        )

        // Fail-fast when offline, responsive-data service type. Must run before
        // the first network call resolves `shared`. Debug layers Pulse's proxy
        // delegate on the same tuned configuration so its behaviour matches.
        #if DEBUG
            URLSessionHTTPTransport.installSharedSession(DebugNetworkInspection.makeInspectedSession(
                configuration: URLSessionHTTPTransport.interactiveConfiguration(),
            ))
        #else
            URLSessionHTTPTransport.installSharedSession(
                URLSession(configuration: URLSessionHTTPTransport.interactiveConfiguration()),
            )
        #endif
    }
}
