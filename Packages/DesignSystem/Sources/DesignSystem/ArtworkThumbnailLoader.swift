import UIKit

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

    /// Fetches (through the shared `URLCache`) and decodes artwork at
    /// `maxPixelSize`, returning a cached thumbnail when one exists.
    /// Runs off the main actor; returns `nil` on any failure — callers show
    /// their placeholder, matching the `AsyncImage` contract this replaces.
    public static func thumbnail(for url: URL?, maxPixelSize: CGFloat) async -> UIImage? {
        guard let url, maxPixelSize > 0 else { return nil }

        let key = "\(Int(maxPixelSize.rounded(.up)))|\(url.absoluteString)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200 ..< 300).contains($0.statusCode) }) ?? true,
              let image = ImageDownsampler.decode(data, maxPixelSize: maxPixelSize)
        else { return nil }

        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }
}
