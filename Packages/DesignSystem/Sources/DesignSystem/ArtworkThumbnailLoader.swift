import Foundation
import RadioDirectory
import UIKit

/// Decoded-thumbnail loading for station artwork in list rows, cards, and the
/// mini-player — the small, many-instance surfaces.
///
/// Decoding goes through ``ArtworkImageSource``: ImageIO downsamples to
/// `maxPixelSize` off the main thread, so a cell only ever holds a cell-sized
/// bitmap. With the app's pipeline registered, in-flight requests for the same
/// URL coalesce and the decoded bitmap is reused from memory (or the encoded
/// original from disk) instead of being fetched again on every cell reuse.
public nonisolated enum ArtworkThumbnailLoader {
    /// Fetches and decodes artwork at `maxPixelSize`, returning a cached
    /// thumbnail when one exists. Returns `nil` on any failure — callers show
    /// their placeholder. Cancelling the caller (a row scrolled away) does not
    /// cancel a download already under way; it completes into the cache.
    ///
    /// Defaults to `.artwork` rather than `.shared`: a row's thumbnail loads
    /// while the station is streaming, and `.artwork`'s `.background` service
    /// type keeps it from competing with that stream on a weak connection
    /// (see `URLSessionHTTPTransport.artworkConfiguration()`).
    public static func thumbnail(
        for url: URL?,
        maxPixelSize: CGFloat,
        transport: any HTTPTransporting = URLSessionHTTPTransport.artwork,
    ) async -> UIImage? {
        guard let url, maxPixelSize > 0 else { return nil }
        return await ArtworkImageSource.image(
            url,
            maxPixelSize: maxPixelSize,
            isPrefetch: false,
            transport: transport,
        )
    }

    /// Warms the cache for artwork about to scroll into view, so a row's own
    /// load finds it already decoded — or joins the in-flight download —
    /// instead of starting cold as the row appears.
    ///
    /// Fire-and-forget: failures are silent. A URL that is already cached is
    /// a memory hit inside the pipeline, so calling this from every row's
    /// `onAppear` with an overlapping look-ahead window stays cheap.
    ///
    /// Skipped entirely in Low Power Mode, and routed over the speculative
    /// transport (see ``URLSessionHTTPTransport/speculativeConfiguration()``) so
    /// Low Data Mode and cellular suppress it too. Both are deliberate: this is
    /// the one artwork path nobody is waiting on, so it's the first thing that
    /// should stop when the device is trying to conserve. A row that scrolls
    /// into view still loads its own artwork over the `.artwork` session — the
    /// listener just pays the decode at that moment instead of ahead of time.
    public static func prefetch(
        _ urls: [URL?],
        maxPixelSize: CGFloat,
        transport: any HTTPTransporting = URLSessionHTTPTransport.speculative,
    ) {
        guard maxPixelSize > 0 else { return }
        // Read per call rather than cached: Low Power Mode flips mid-session
        // (the system enables it at 20%, the user can toggle it any time), and
        // prefetching is re-driven by every row that appears, so sampling here
        // tracks the current state without needing a change observer.
        guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }

        for case let url? in urls {
            Task(priority: .utility) {
                _ = await ArtworkImageSource.image(
                    url,
                    maxPixelSize: maxPixelSize,
                    isPrefetch: true,
                    transport: transport,
                )
            }
        }
    }
}
