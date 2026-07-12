import Foundation
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public nonisolated enum ImageIODownsampler {
#if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
    /// Decodes `data` to a bitmap whose longer edge is at most `maxPixelSize`.
    public static func decodeCGImage(_ data: Data, maxPixelSize: CGFloat) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        // `kCGImageSourceThumbnailMaxPixelSize` is an integer pixel count.
        // Callers pass a `CGFloat` for API convenience, so coerce to a positive
        // `Int` here rather than letting a fractional value bridge to CFNumber.
        let maxPixelDimension = max(1, Int(maxPixelSize.rounded()))
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
        ] as [CFString: Any] as CFDictionary

        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
    }

    /// Downsamples and re-encodes the image to the requested output type.
    public static func encode(
        _ data: Data,
        maxPixelSize: CGFloat,
        outputType: UTType
    ) -> Data? {
        guard let cgImage = decodeCGImage(data, maxPixelSize: maxPixelSize) else {
            return nil
        }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded as CFMutableData,
            outputType.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return encoded as Data
    }
#endif
}
