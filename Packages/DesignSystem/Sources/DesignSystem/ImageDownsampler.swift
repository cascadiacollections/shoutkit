import ImageIODownsample
import UIKit

/// Bounded-memory bitmap decoding via ImageIO thumbnailing.
///
/// `UIImage(data:)` decodes at the source's native resolution, so a station
/// favicon or album scan that happens to be 2000×2000 pins ~16 MB of bitmap
/// behind a 56 pt cell. `CGImageSourceCreateThumbnailAtIndex` decodes straight
/// to the target size instead — decoded memory scales with what the screen
/// needs, never with what the server sent.
nonisolated enum ImageDownsampler {
    /// Decodes `data` to a bitmap whose longer edge is at most `maxPixelSize`
    /// (smaller sources decode at native size — ImageIO does not upscale).
    /// `ShouldCacheImmediately` forces the decode to happen here, on the
    /// calling (non-main) executor, so the first render never pays a lazy
    /// decode on the main thread mid-scroll.
    static func decode(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let cgImage = ImageIODownsampler.decodeCGImage(data, maxPixelSize: maxPixelSize) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
