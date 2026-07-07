import SwiftUI
import UIKit

/// Station artwork decoded off the main actor, carrying the two things
/// `AsyncImage` can't provide: the bitmap's real pixel size and a 3×3
/// dominant-color grid. Radio-directory favicons are frequently tiny
/// (median ~180px across Radio Browser's most-clicked stations), so consumers
/// need the pixel size to avoid blurry upscales and the color grid to build
/// resolution-independent ambient backdrops.
public struct LoadedArtwork: Sendable {
    public let image: UIImage
    public let pixelSize: CGSize
    /// Row-major 3×3 grid of box-filtered colors, top-left first — shaped to
    /// feed a `MeshGradient` directly. Empty if sampling failed.
    public let paletteGrid: [Color]

    /// The most vibrant palette sample, tuned for use as a control tint over
    /// glass. `nil` when the artwork is effectively monochrome — callers
    /// should fall back to the brand accent.
    public let accentColor: Color?

    /// The bitmap's shorter edge in pixels — the honest measure of how far
    /// the artwork can be scaled up before it goes soft.
    public var minPixelDimension: CGFloat {
        min(pixelSize.width, pixelSize.height)
    }
}

public enum ArtworkLoader {
    /// Loads through the shared `URLCache`, so backdrop and hero requests for
    /// the same station coalesce into a single network fetch.
    public nonisolated static func load(_ url: URL?) async -> LoadedArtwork? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200 ..< 300).contains($0.statusCode) }) ?? true,
              let image = UIImage(data: data),
              let cgImage = image.cgImage
        else { return nil }

        let samples = hsbSamples(from: cgImage)
        return LoadedArtwork(
            image: image,
            pixelSize: CGSize(width: cgImage.width, height: cgImage.height),
            paletteGrid: samples.map(ambientColor),
            accentColor: accentColor(from: samples)
        )
    }

    private struct HSBSample {
        let hue: CGFloat
        let saturation: CGFloat
        let brightness: CGFloat
    }

    /// Downsamples the bitmap to a 3×3 grid (CoreGraphics box-filters the
    /// areas) and returns the samples as HSB, top-left first.
    private nonisolated static func hsbSamples(from cgImage: CGImage) -> [HSBSample] {
        let side = 3
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: &pixels,
                  width: side,
                  height: side,
                  bitsPerComponent: 8,
                  bytesPerRow: side * 4,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return [] }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        // CoreGraphics rows run bottom-up; reverse so the grid reads top-first.
        return (0 ..< side).reversed().flatMap { row in
            (0 ..< side).map { column in
                let offset = (row * side + column) * 4
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                UIColor(
                    red: CGFloat(pixels[offset]) / 255,
                    green: CGFloat(pixels[offset + 1]) / 255,
                    blue: CGFloat(pixels[offset + 2]) / 255,
                    alpha: 1
                ).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
                return HSBSample(hue: hue, saturation: saturation, brightness: brightness)
            }
        }
    }

    /// Nudges a sample toward legible ambient tones: mild saturation boost,
    /// brightness clamped away from pure white/black so a favicon's flat
    /// background can't wash out the mesh.
    private nonisolated static func ambientColor(_ sample: HSBSample) -> Color {
        Color(
            hue: sample.hue,
            saturation: min(1, sample.saturation * 1.25),
            brightness: min(0.88, max(0.22, sample.brightness))
        )
    }

    /// Elects the most vibrant sample — high saturation near mid brightness —
    /// and re-tunes it for control duty: saturated enough to read as a tint,
    /// brightness held to a band that keeps white glyphs legible on it.
    private nonisolated static func accentColor(from samples: [HSBSample]) -> Color? {
        func vibrancy(_ sample: HSBSample) -> CGFloat {
            sample.saturation * (1 - abs(sample.brightness - 0.55))
        }

        guard let best = samples.max(by: { vibrancy($0) < vibrancy($1) }),
              best.saturation >= 0.15
        else { return nil }

        return Color(
            hue: best.hue,
            saturation: max(0.55, min(1, best.saturation * 1.3)),
            brightness: min(0.72, max(0.38, best.brightness))
        )
    }
}
