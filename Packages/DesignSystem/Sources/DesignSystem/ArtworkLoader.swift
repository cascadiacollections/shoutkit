import OrderedCollections
import RadioDirectory
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
    /// The decoded bitmap's pixel size. Decoding is capped at the loader's
    /// 840 px ceiling, so for oversized sources this is the downsampled size —
    /// every consumer decision (upscale caps, blur-wash gates) resolves well
    /// below the ceiling, so the distinction never shows.
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
    /// Decode ceiling in pixels. The largest surface this pipeline feeds is
    /// the 280 pt Now Playing hero — 840 px on a 3× display; the ambient
    /// backdrop consumes the same bitmap through a heavy blur, so it needs no
    /// more resolution either. Decoding through ImageIO with this cap keeps
    /// an oversized favicon from pinning a multi-megabyte bitmap.
    /// `nonisolated`: read from the nonisolated decode pipeline, and the
    /// package's main-actor default would otherwise isolate it.
    private nonisolated static let maxDecodePixelSize: CGFloat = 840
    private nonisolated static let requestCachePolicy: URLRequest.CachePolicy = .reloadRevalidatingCacheData

    /// Loads and decodes artwork, coalescing concurrent and repeated requests
    /// for the same URL. The Now Playing surface asks for the same artwork
    /// from several views at once (backdrop, hero, tint) — the store hands
    /// them one shared decode + palette pass instead of three.
    ///
    /// Runs over `.artwork` rather than `.shared`: this hero art loads
    /// alongside an active audio stream, and `.artwork`'s `.background`
    /// service type keeps it from competing with the stream for priority on
    /// a weak connection (see `URLSessionHTTPTransport.artworkConfiguration()`).
    public nonisolated static func load(
        _ url: URL?,
        transport: any HTTPTransporting = URLSessionHTTPTransport.artwork
    ) async -> LoadedArtwork? {
        guard let url else { return nil }
        return await ArtworkStore.shared.artwork(for: url, transport: transport)
    }

    /// The uncached fetch/decode pipeline: loads through the shared
    /// `URLCache`, downsample-decodes to the display ceiling, and box-filters
    /// a 3×3 palette — all off the main actor.
    fileprivate nonisolated static func fetchAndDecode(
        _ url: URL,
        transport: any HTTPTransporting
    ) async -> LoadedArtwork? {
        var request = URLRequest(url: url)
        request.cachePolicy = requestCachePolicy

        guard let data = try? await transport.data(for: request),
              let image = ImageDownsampler.decode(data, maxPixelSize: maxDecodePixelSize),
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

    /// Deduplicates artwork work per URL: in-flight and completed loads share
    /// one map entry, so a second caller awaits the first caller's task
    /// instead of re-fetching and re-decoding. Bounded FIFO — in practice only
    /// the current and previous track's art are ever live at once.
    private actor ArtworkStore {
        static let shared = ArtworkStore()

        // swiftlint:disable:next nesting
        private struct Entry {
            let token = UUID()
            let task: Task<LoadedArtwork?, Never>
        }

        private var entries: OrderedDictionary<URL, Entry> = [:]
        private let capacity = 6

        /// Purges the store when the system reports memory pressure, so the
        /// worst case (six hero-sized bitmaps, ~17 MB) is always reclaimable
        /// on constrained devices. A dispatch source rather than
        /// `didReceiveMemoryWarning`: no UIKit plumbing, and it also fires
        /// for pressure while backgrounded. Installed lazily on first use so
        /// the actor's init stays trivial.
        private var memoryPressureSource: DispatchSourceMemoryPressure?

        func artwork(for url: URL, transport: any HTTPTransporting) async -> LoadedArtwork? {
            installMemoryPressureSourceIfNeeded()

            if let existing = entries[url] {
                return await existing.task.value
            }

            let entry = Entry(task: Task { await ArtworkLoader.fetchAndDecode(url, transport: transport) })
            entries[url] = entry
            if entries.count > capacity {
                entries.remove(at: 0)
            }

            let artwork = await entry.task.value
            if artwork == nil, entries[url]?.token == entry.token {
                // A transient failure must not pin a miss until eviction.
                entries.removeValue(forKey: url)
            }
            return artwork
        }

        private func installMemoryPressureSourceIfNeeded() {
            guard memoryPressureSource == nil else { return }

            let source = DispatchSource.makeMemoryPressureSource(
                eventMask: [.warning, .critical],
                queue: .global(qos: .utility)
            )
            // Explicitly @Sendable: the handler leaves the actor and only
            // captures a weak actor reference, which is safe to send.
            let handler: @Sendable () -> Void = { [weak self] in
                guard let self else { return }
                Task { await self.purge() }
            }
            source.setEventHandler(handler: handler)
            source.activate()
            memoryPressureSource = source
        }

        /// Drops everything, including in-flight tasks — callers already
        /// awaiting a task hold their own reference, so their loads still
        /// complete; only the cached results are released.
        private func purge() {
            entries.removeAll()
        }
    }

    struct HSBSample {
        let hue: CGFloat
        let saturation: CGFloat
        let brightness: CGFloat
    }

    /// Downsamples the bitmap to a 3×3 grid (CoreGraphics box-filters the
    /// areas) and returns the samples as HSB, top-left first.
    private nonisolated static func hsbSamples(from cgImage: CGImage) -> [HSBSample] {
        let side = 3
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        // The buffer is passed via `withUnsafeMutableBytes` (not `&pixels`):
        // an inout-to-pointer conversion is only valid for the duration of
        // the initializer call, but the context writes through the pointer
        // again later, in `draw`.
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: buffer.baseAddress,
                      width: side,
                      height: side,
                      bitsPerComponent: 8,
                      bytesPerRow: side * 4,
                      space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return false }

            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard rendered else { return [] }

        // A bitmap context's first scanline in memory is the drawn image's TOP
        // row, so reading rows in buffer order already yields top-left first.
        return (0 ..< side).flatMap { row in
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

    nonisolated static func paletteHSBSamples(from cgImage: CGImage) -> [HSBSample] {
        hsbSamples(from: cgImage)
    }
}
