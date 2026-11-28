import Foundation
import ImageIODownsample
import os
import RadioDirectory
import UIKit

/// One artwork image a DesignSystem surface needs decoded.
public nonisolated struct ArtworkImageRequest: Sendable {
    public let url: URL
    /// Longest edge of the decoded bitmap, in pixels.
    public let maxPixelSize: CGFloat
    /// Warming a row that is not on screen yet; yields to visible work.
    public let isPrefetch: Bool
    /// The session to fetch over (`.artwork` for something on screen,
    /// `.speculative` for prefetch, a fake in tests).
    public let transport: any HTTPTransporting
}

/// Where DesignSystem's artwork bitmaps come from.
///
/// DesignSystem ships no image-loading library, so it stays adoptable on its
/// own (MIT, no heavyweight dependencies). An app that wants caching registers
/// a loader once at launch; ShoutKit registers its Nuke pipeline from the
/// app-side `ArtworkPipelineNuke` package, the same shape as
/// `registerProductionPlaybackEngine()`. With nothing registered — previews,
/// package tests, an outside adopter — each load is a plain fetch through the
/// request's transport and an ImageIO downsample, with no cache.
public nonisolated enum ArtworkImageSource {
    /// Returns the decoded bitmap, or `nil` on any failure.
    public typealias Loader = @Sendable (ArtworkImageRequest) async -> CGImage?

    private static let registered = OSAllocatedUnfairLock<Loader?>(initialState: nil)

    /// Installs the loader every artwork surface uses from now on. Call once,
    /// before the first view loads artwork; a later call replaces it.
    public static func register(_ loader: @escaping Loader) {
        registered.withLock { $0 = loader }
    }

    /// Decodes `url` through the registered loader.
    ///
    /// The load runs in an unstructured task, so cancelling the caller (a row
    /// scrolled away, a hero replaced) returns early without tearing down a
    /// download that has started: it finishes and lands in the loader's cache
    /// for the next appearance. That is the behavior the pre-Nuke
    /// `InFlightThumbnails` and `ArtworkStore` had (DECISIONS.md, 2026-11-28).
    static func image(
        _ url: URL,
        maxPixelSize: CGFloat,
        isPrefetch: Bool,
        transport: any HTTPTransporting,
    ) async -> UIImage? {
        let request = ArtworkImageRequest(
            url: url,
            maxPixelSize: maxPixelSize,
            isPrefetch: isPrefetch,
            transport: transport,
        )
        let loader = registered.withLock { $0 } ?? uncached
        let cgImage = await Task { await loader(request) }.value
        return cgImage.map { UIImage(cgImage: $0) }
    }

    /// The unregistered default: fetch, reject an HTML body (`imageData`),
    /// and decode straight to the requested size.
    static let uncached: Loader = { request in
        var urlRequest = URLRequest(url: request.url)
        urlRequest.cachePolicy = .reloadRevalidatingCacheData
        guard let data = try? await request.transport.imageData(for: urlRequest) else { return nil }
        return ImageIODownsampler.decodeCGImage(data, maxPixelSize: request.maxPixelSize)
    }
}
