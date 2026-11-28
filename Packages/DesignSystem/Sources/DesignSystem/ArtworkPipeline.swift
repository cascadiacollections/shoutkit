import Foundation
import Nuke
import os
import RadioDirectory
import UIKit

/// How urgently a decoded bitmap is needed. Prefetch yields to a visible row
/// or the Now Playing hero.
nonisolated enum ArtworkFetchPriority: Sendable {
    case visible
    case prefetch
}

/// One Nuke pipeline for station logos and Now Playing artwork: memory cache,
/// disk cache, in-flight coalescing, and ImageIO thumbnail decoding off the
/// main thread. Palette extraction stays with the callers; Nuke does not know
/// about it.
nonisolated enum ArtworkImages {
    nonisolated static func decoded(
        _ url: URL,
        maxPixelSize: CGFloat,
        priority: ArtworkFetchPriority,
        transport: any HTTPTransporting,
    ) async -> UIImage? {
        let route = ArtworkPipelineStore.shared.route(for: transport)
        let request = makeRequest(
            url: url,
            maxPixelSize: maxPixelSize,
            priority: priority,
            speculative: route.speculative,
        )
        return try? await route.pipeline.image(for: request)
    }

    private nonisolated static func makeRequest(
        url: URL,
        maxPixelSize: CGFloat,
        priority: ArtworkFetchPriority,
        speculative: Bool,
    ) -> ImageRequest {
        var urlRequest = URLRequest(url: url)
        // Nuke's data cache is the disk copy. Ignoring URLCache here keeps a
        // second copy of the same bytes from accumulating in the shared cache
        // the directory JSON still uses.
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        if speculative {
            urlRequest.setValue(LaneArtworkDataLoader.speculative, forHTTPHeaderField: LaneArtworkDataLoader.header)
        }
        var request = ImageRequest(urlRequest: urlRequest)
        // ImageIO thumbnail generation, during decode, capped at the pixel
        // size the caller asked for. This is the off-main downsample; a later
        // resize processor would have decoded the full bitmap first.
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: Float(maxPixelSize))
        request.priority = priority == .prefetch ? .low : .normal
        return request
    }
}

/// Builds a pipeline with the given ceilings. Split from the store so the
/// store's routing stays under the function-length lint.
nonisolated enum ArtworkPipelineFactory {
    static func make(
        dataLoader: any DataLoading,
        limits: ArtworkCacheLimits,
        diskName: String,
    ) -> ImagePipeline {
        let memory = ImageCache(costLimit: limits.memoryCostBytes, countLimit: limits.memoryCountLimit)
        memory.entryCostLimit = limits.memoryEntryCostFraction
        let disk = try? DataCache(name: diskName)
        disk?.sizeLimit = limits.diskByteLimit
        return ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = disk
            $0.imageCache = memory
            $0.isTaskCoalescingEnabled = true
            // One encoded original per URL, then a thumbnail per display size.
            // List rows and the Now Playing hero share the download.
            $0.dataCachePolicy = .storeOriginalData
        }
    }
}

/// Routes production sessions onto one pipeline (so prefetch and a visible row
/// share caches) and gives every other transport a pipeline of its own.
final nonisolated class ArtworkPipelineStore: @unchecked Sendable {
    nonisolated static let shared = ArtworkPipelineStore()

    private let production: ImagePipeline
    private let artworkID: ObjectIdentifier?
    private let speculativeID: ObjectIdentifier?
    private let custom = OSAllocatedUnfairLock<[ObjectIdentifier: ImagePipeline]>(initialState: [:])

    private init() {
        artworkID = ArtworkTransportIdentity.identifier(of: URLSessionHTTPTransport.artwork)
        speculativeID = ArtworkTransportIdentity.identifier(of: URLSessionHTTPTransport.speculative)
        production = ArtworkPipelineFactory.make(
            dataLoader: LaneArtworkDataLoader(),
            limits: .current,
            diskName: "com.cascadiacollections.holmdel.artwork",
        )
    }

    func route(for transport: any HTTPTransporting) -> (pipeline: ImagePipeline, speculative: Bool) {
        let identifier = ArtworkTransportIdentity.identifier(of: transport)
        if let identifier, identifier == artworkID {
            return (production, false)
        }
        if let identifier, identifier == speculativeID {
            return (production, true)
        }
        guard let identifier else {
            return (ephemeralPipeline(for: transport), false)
        }
        let existing = custom.withLock { $0[identifier] }
        if let existing {
            return (existing, false)
        }
        let created = ArtworkPipelineFactory.make(
            dataLoader: TransportArtworkDataLoader(transport: transport),
            limits: .current,
            diskName: "com.cascadiacollections.holmdel.artwork.\(UUID().uuidString)",
        )
        let stored = custom.withLock { cache -> ImagePipeline in
            if let winner = cache[identifier] {
                return winner
            }
            cache[identifier] = created
            return created
        }
        return (stored, false)
    }

    private func ephemeralPipeline(for transport: any HTTPTransporting) -> ImagePipeline {
        ArtworkPipelineFactory.make(
            dataLoader: TransportArtworkDataLoader(transport: transport),
            limits: .current,
            diskName: "com.cascadiacollections.holmdel.artwork.\(UUID().uuidString)",
        )
    }
}

/// Class identity of a transport, when it has one. Actors (the production
/// sessions, and the fakes tests use) compare equal across calls, which is
/// what lets two loads share a pipeline. A struct transport has no identity;
/// those get a one-off pipeline and do not coalesce across calls.
nonisolated enum ArtworkTransportIdentity {
    static func identifier(of transport: any HTTPTransporting) -> ObjectIdentifier? {
        func open(_ value: some HTTPTransporting) -> ObjectIdentifier? {
            guard let object = value as? AnyObject else { return nil }
            return ObjectIdentifier(object)
        }
        return open(transport)
    }
}
