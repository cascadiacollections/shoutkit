import UIKit
import RadioDirectory

/// Decoded-thumbnail loading for station artwork in list rows, cards, and the
/// mini-player — the small, many-instance surfaces.
///
/// `AsyncImage` decodes at the bitmap's native resolution and re-decodes on
/// every cell reuse (its only cache is `URLCache`'s raw bytes). Here the bytes
/// still come through the shared `URLCache`, but decoding goes through ImageIO
/// downsampling so a cell only ever holds a cell-sized bitmap, and the decoded
/// result lives in an `NSCache` — the platform cache that sizes itself to the
/// device and evicts automatically under memory pressure, which is exactly the
/// behavior wanted on older, RAM-constrained hardware.
public nonisolated enum ArtworkThumbnailLoader {
    /// Decoded thumbnails keyed by URL + target pixel size, costed in bitmap
    /// bytes. The ceiling is modest — a 168 px list thumb is ~110 KB, so this
    /// holds several screenfuls — and NSCache shrinks it further on its own
    /// when the system needs memory back.
    ///
    /// `nonisolated(unsafe)` only silences Sendable checking: NSCache is
    /// documented thread-safe.
    private nonisolated(unsafe) static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    /// Coalesces concurrent loads of the same key so a row's own `.task` and a
    /// prefetch for the same artwork share one fetch/decode instead of racing.
    private static let inFlight = InFlightThumbnails()

    /// Fetches (through the shared `URLCache`) and decodes artwork at
    /// `maxPixelSize`, returning a cached thumbnail when one exists.
    /// Runs off the main actor; returns `nil` on any failure — callers show
    /// their placeholder, matching the `AsyncImage` contract this replaces.
    public static func thumbnail(
        for url: URL?,
        maxPixelSize: CGFloat,
        transport: any HTTPTransporting = URLSessionHTTPTransport.shared
    ) async -> UIImage? {
        guard let url, maxPixelSize > 0 else { return nil }

        let key = cacheKey(url: url, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        return await inFlight.thumbnail(
            forKey: key,
            url: url,
            maxPixelSize: maxPixelSize,
            transport: transport
        )
    }

    /// Warms the thumbnail cache for artwork about to scroll into view, so a
    /// row's own `.task` finds it already decoded — or joins the in-flight
    /// decode — instead of starting cold as the row appears.
    ///
    /// Fire-and-forget: failures are silent, and a URL that is already cached or
    /// already in flight is skipped, so calling this from every row's `onAppear`
    /// with an overlapping look-ahead window is cheap.
    public static func prefetch(
        _ urls: [URL?],
        maxPixelSize: CGFloat,
        transport: any HTTPTransporting = URLSessionHTTPTransport.shared
    ) {
        guard maxPixelSize > 0 else { return }

        for case let url? in urls {
            let key = cacheKey(url: url, maxPixelSize: maxPixelSize)
            guard cache.object(forKey: key as NSString) == nil else { continue }
            Task(priority: .utility) {
                _ = await inFlight.thumbnail(
                    forKey: key,
                    url: url,
                    maxPixelSize: maxPixelSize,
                    transport: transport
                )
            }
        }
    }

    private static func cacheKey(url: URL, maxPixelSize: CGFloat) -> String {
        "\(Int(maxPixelSize.rounded(.up)))|\(url.absoluteString)"
    }

    /// The uncached fetch/decode/store path. `key` is passed through so the
    /// coalescing actor and this helper agree on the cache identity without
    /// recomputing it.
    fileprivate static func fetchDecodeAndCache(
        key: String,
        url: URL,
        maxPixelSize: CGFloat,
        transport: any HTTPTransporting
    ) async -> UIImage? {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad

        guard let data = try? await transport.data(for: request),
              let image = ImageDownsampler.decode(data, maxPixelSize: maxPixelSize)
        else { return nil }

        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: key as NSString, cost: cost)
        return image
    }
}

/// Deduplicates in-flight thumbnail loads by cache key: a second caller (a
/// prefetch, or a second visible row for the same artwork) awaits the first
/// caller's task instead of issuing a duplicate fetch and decode. The entry is
/// dropped once the load completes so a later miss re-fetches rather than pinning
/// a stale result — the decoded bitmap lives in the `NSCache`, not here.
private actor InFlightThumbnails {
    private var tasks: [String: Task<UIImage?, Never>] = [:]

    func thumbnail(
        forKey key: String,
        url: URL,
        maxPixelSize: CGFloat,
        transport: any HTTPTransporting
    ) async -> UIImage? {
        if let existing = tasks[key] {
            return await existing.value
        }

        // Unstructured so a caller that gets cancelled (row scrolled away) doesn't
        // tear down a decode a still-visible row — or a prefetch — is awaiting.
        let task = Task {
            await ArtworkThumbnailLoader.fetchDecodeAndCache(
                key: key,
                url: url,
                maxPixelSize: maxPixelSize,
                transport: transport
            )
        }
        tasks[key] = task
        let image = await task.value
        tasks.removeValue(forKey: key)
        return image
    }
}
