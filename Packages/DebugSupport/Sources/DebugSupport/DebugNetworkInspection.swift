import Foundation

#if DEBUG
    import Pulse
#endif

/// Debug-only network inspection. Every Pulse reference in the repo lives in
/// this single app-side file so the boundary stays easy to audit and the
/// reusable packages never declare Pulse at all. The app imports and uses this
/// package only under `#if DEBUG`, and Release strips the framework from the
/// bundle (see Package.swift); CI checks the Release build for Pulse symbols.
public enum DebugNetworkInspection {
    /// A session built from `configuration` with Pulse's proxy delegate layered
    /// on top, so its requests show up in Pulse without any call site knowing.
    ///
    /// Returned rather than installed: installing needs RadioDirectory's
    /// `URLSessionHTTPTransport`, and this package must not depend on
    /// RadioDirectory (see Package.swift). `AppDependencies.bootstrap()`
    /// installs it as `URLSessionHTTPTransport.shared` — the transport
    /// Radio-Browser/SHOUTcast lookups default to — built from the same
    /// latency-tuned configuration the Release session uses.
    ///
    /// Artwork traffic doesn't go through it. In-app artwork runs over
    /// `URLSessionHTTPTransport.artwork` so it doesn't compete with the audio
    /// stream on a weak connection (see `artworkConfiguration()`); artwork the
    /// system now-playing surfaces are blocked on runs over
    /// `.nowPlayingArtwork` (see `nowPlayingArtworkConfiguration()`). Neither
    /// session is currently wired through Pulse.
    public static func makeInspectedSession(configuration: URLSessionConfiguration) -> URLSession {
        #if DEBUG
            URLSession(
                configuration: configuration,
                delegate: URLSessionProxyDelegate(logger: .shared),
                delegateQueue: nil,
            )
        #else
            URLSession(configuration: configuration)
        #endif
    }
}

/// Debug-only messages into Pulse's console, for the non-network diagnostics
/// in this package (``DebugResourceMonitor``). Here rather than beside its
/// caller so this file stays the only one that names Pulse. Compiles to a no-op
/// in Release.
enum DebugConsoleLog {
    static func record(
        _ message: String,
        label: String,
        isWarning: Bool,
        metadata: [String: String],
    ) {
        #if DEBUG
            LoggerStore.shared.storeMessage(
                label: label,
                level: isWarning ? .warning : .info,
                message: message,
                metadata: metadata.mapValues { .string($0) },
            )
        #endif
    }
}
