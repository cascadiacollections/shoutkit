import CoreGraphics
import Foundation
import Nuke
import os
import RadioDirectory

/// The app's artwork pipeline: one Nuke `ImagePipeline` for station logos and
/// Now Playing art, with a memory cache, a disk cache, in-flight coalescing,
/// and ImageIO thumbnail decoding off the main thread. Palette extraction,
/// placeholders, and the album-art fallback stay in `DesignSystem`; Nuke does
/// not know about them.
///
/// The app target registers ``image(for:maxPixelSize:isPrefetch:transport:)``
/// with `DesignSystem.ArtworkImageSource` during bootstrap.
public enum NukeArtworkPipeline {
    /// Fetches and decodes `url` to at most `maxPixelSize` on the longer edge.
    /// `nil` on any failure; callers show their placeholder.
    ///
    /// `URLSessionHTTPTransport.artwork` and `.speculative` share the
    /// production pipeline and its caches. Any other transport gets a pipeline
    /// of its own with no disk cache.
    public static func image(
        for url: URL,
        maxPixelSize: CGFloat,
        isPrefetch: Bool,
        transport: any HTTPTransporting,
    ) async -> CGImage? {
        await ArtworkPipelineStore.shared.image(
            for: url,
            maxPixelSize: maxPixelSize,
            isPrefetch: isPrefetch,
            transport: transport,
        )
    }
}

/// Which production session a request goes out on.
enum ArtworkLane: Sendable {
    case visible
    case speculative

    /// Part of Nuke's download key, which is URL, cache policy, and
    /// `allowsCellularAccess` — not headers. If both lanes used one policy, a
    /// visible request would join a queued speculative download for the same
    /// URL and inherit the speculative session's refusal on cellular and in
    /// Low Data Mode, leaving the placeholder up. The speculative value is a
    /// key only: ``LaneArtworkDataLoader`` sends both lanes with the visible
    /// policy.
    ///
    /// `.reloadIgnoringLocalCacheData` skips reading `URLCache`, because
    /// Nuke's disk cache is checked first; responses are still *written* to
    /// `URLCache.shared`. That is relied on: the lock screen's
    /// `nowPlayingArtwork` session reads the same URL with
    /// `.returnCacheDataElseLoad` and is served those bytes instead of
    /// downloading them again.
    var cachePolicy: URLRequest.CachePolicy {
        switch self {
        case .visible: .reloadIgnoringLocalCacheData
        case .speculative: .reloadIgnoringLocalAndRemoteCacheData
        }
    }
}

enum ArtworkRequests {
    static func make(
        url: URL,
        maxPixelSize: CGFloat,
        isPrefetch: Bool,
        lane: ArtworkLane,
    ) -> ImageRequest {
        var urlRequest = URLRequest(url: url)
        urlRequest.cachePolicy = lane.cachePolicy
        if lane == .speculative {
            urlRequest.setValue(LaneArtworkDataLoader.speculative, forHTTPHeaderField: LaneArtworkDataLoader.header)
        }
        var request = ImageRequest(urlRequest: urlRequest)
        // ImageIO thumbnail generation, during decode, capped at the pixel
        // size the caller asked for. This is the off-main downsample; a later
        // resize processor would have decoded the full bitmap first.
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: Float(maxPixelSize))
        request.priority = isPrefetch ? .low : .normal
        return request
    }
}

/// Builds a pipeline with the given ceilings.
enum ArtworkPipelineFactory {
    static func make(
        dataLoader: any DataLoading,
        limits: ArtworkCacheLimits,
        dataCache: DataCache?,
    ) -> ImagePipeline {
        let memory = ImageCache(costLimit: limits.memoryCostBytes, countLimit: limits.memoryCountLimit)
        memory.entryCostLimit = limits.memoryEntryCostFraction
        dataCache?.sizeLimit = limits.diskByteLimit
        return ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = memory
            $0.isTaskCoalescingEnabled = true
            // One encoded original per URL, then a thumbnail per display size.
            // List rows and the Now Playing hero share the download.
            $0.dataCachePolicy = .storeOriginalData
        }
    }
}

/// Routes the two production sessions onto one pipeline (so prefetch and a
/// visible row share caches, though never a download) and gives every other
/// transport a memory-only pipeline that lives as long as the transport does.
final class ArtworkPipelineStore: @unchecked Sendable {
    static let productionDiskName = "com.cascadiacollections.holmdel.artwork"

    static let shared = ArtworkPipelineStore(
        visible: URLSessionHTTPTransport.artwork,
        speculative: URLSessionHTTPTransport.speculative,
        limits: .current,
        dataCache: try? DataCache(name: productionDiskName),
    )

    private let production: ImagePipeline
    private let visibleID: ObjectIdentifier?
    private let speculativeID: ObjectIdentifier?
    private let limits: ArtworkCacheLimits
    private let custom = OSAllocatedUnfairLock<[ObjectIdentifier: CustomPipeline]>(uncheckedState: [:])

    /// `visible` and `speculative` are the production lanes. Injectable so
    /// tests can drive the production pipeline's lane routing with fakes.
    init(
        visible: any HTTPTransporting,
        speculative: any HTTPTransporting,
        limits: ArtworkCacheLimits,
        dataCache: DataCache?,
    ) {
        visibleID = ArtworkTransportIdentity.identifier(of: visible)
        speculativeID = ArtworkTransportIdentity.identifier(of: speculative)
        self.limits = limits
        production = ArtworkPipelineFactory.make(
            dataLoader: LaneArtworkDataLoader(visible: visible, speculative: speculative),
            limits: limits,
            dataCache: dataCache,
        )
    }

    func image(
        for url: URL,
        maxPixelSize: CGFloat,
        isPrefetch: Bool,
        transport: any HTTPTransporting,
    ) async -> CGImage? {
        let route = route(for: transport)
        let request = ArtworkRequests.make(
            url: url,
            maxPixelSize: maxPixelSize,
            isPrefetch: isPrefetch,
            lane: route.lane,
        )
        guard let image = try? await route.pipeline.image(for: request) else { return nil }
        #if canImport(UIKit)
            return image.cgImage
        #else
            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }

    func route(for transport: any HTTPTransporting) -> (pipeline: ImagePipeline, lane: ArtworkLane) {
        guard let object = ArtworkTransportIdentity.object(of: transport) else {
            // A value-type transport has no identity to key on, so it gets a
            // pipeline for this one load and nothing is retained.
            return (memoryOnlyPipeline(TransportArtworkDataLoader(retaining: transport)), .visible)
        }
        let identifier = ObjectIdentifier(object)
        if identifier == visibleID {
            return (production, .visible)
        }
        if identifier == speculativeID {
            return (production, .speculative)
        }
        let pipeline = custom.withLock { cache -> ImagePipeline in
            // `owner === object` rejects an entry whose transport died and
            // whose address was reused by this one.
            if let entry = cache[identifier], entry.owner === object {
                return entry.pipeline
            }
            cache = cache.filter { $0.value.owner != nil }
            let created = memoryOnlyPipeline(TransportArtworkDataLoader(weaklyReferencing: object))
            cache[identifier] = CustomPipeline(owner: object, pipeline: created)
            return created
        }
        return (pipeline, .visible)
    }

    /// Pipelines held for live non-production transports. For tests.
    var customPipelineCount: Int {
        custom.withLock { cache in cache.values.count(where: { $0.owner != nil }) }
    }

    /// No disk cache: a non-production pipeline must not leave a directory in
    /// Caches behind it.
    private func memoryOnlyPipeline(_ loader: TransportArtworkDataLoader) -> ImagePipeline {
        ArtworkPipelineFactory.make(dataLoader: loader, limits: limits, dataCache: nil)
    }
}

private struct CustomPipeline: @unchecked Sendable {
    weak var owner: AnyObject?
    let pipeline: ImagePipeline
}

/// Class identity of a transport, when it has one. Actors (the production
/// sessions, and the fakes tests use) compare equal across calls, which is
/// what lets two loads share a pipeline.
///
/// A struct has no identity. `value as AnyObject` would still succeed for one
/// — Swift boxes it — but the box is new on every call and its address can be
/// reused once it is freed, so keying on it would send one struct transport's
/// requests through another's pipeline. Only class instances qualify.
enum ArtworkTransportIdentity {
    static func object(of transport: any HTTPTransporting) -> (any HTTPTransporting & AnyObject)? {
        func open<Transport: HTTPTransporting>(_ value: Transport) -> (any HTTPTransporting & AnyObject)? {
            guard Transport.self is AnyClass else { return nil }
            return (value as AnyObject) as? any HTTPTransporting & AnyObject
        }
        return open(transport)
    }

    static func identifier(of transport: any HTTPTransporting) -> ObjectIdentifier? {
        object(of: transport).map { ObjectIdentifier($0) }
    }
}
