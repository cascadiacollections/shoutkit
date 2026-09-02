#if canImport(NowPlaying)

import Foundation
import ImageIODownsample
import NowPlaying
import RadioDirectory

/// Artwork residency, fetching, and retry for ``MediaSessionNowPlayingCenter``.
///
/// Split from the main file along the seam the class already had — the identity
/// decision on one side, the bytes behind it on the other — rather than growing
/// past `file_length` and reaching for a `swiftlint:disable`, per the house
/// remedy in `CLAUDE.md`.
@available(iOS 27, macOS 27, tvOS 27, watchOS 27, *)
extension MediaSessionNowPlayingCenter {
    /// URLs the policy may advertise without a fetch first: bytes in hand, or a
    /// fetch already tried and failed. A failed URL stays advertisable on purpose
    /// (2026-08-06) — one we cannot download must not pin the previous track's
    /// cover on screen for the whole next song.
    var readyArtworkURLs: Set<URL> {
        Set(residentArtwork.keys).union(artworkFailures.keys)
    }

    /// Hands the system an `Artwork` for `url`. Once the bytes are resident the
    /// provider answers from memory, so nothing stands between the track-changed
    /// notification and the head unit's cover-art request.
    func artwork(for url: URL?) -> Artwork? {
        guard let url else { return nil }
        if let residentData = residentArtwork[url] {
            return Artwork(id: url.absoluteString) { @Sendable _ in
                try ArtworkRepresentation(data: residentData)
            }
        }
        // Not resident. Since 2026-09-02 the policy only advertises a URL whose
        // bytes are in hand *or* whose fetch already failed, so in practice this
        // is the failed-fetch case: keep the lazy provider so the system gets one
        // more chance at an image rather than none.
        let transport = self.transport
        return Artwork(id: url.absoluteString) { @Sendable _ in
            let data = try await Self.artworkData(for: url, transport: transport)
            return try ArtworkRepresentation(data: data)
        }
    }

    func fetchArtworkIfNeeded(_ url: URL) {
        guard residentArtwork[url] == nil else { return }
        guard artworkFetches[url] == nil else { return }
        if let failure = artworkFailures[url] {
            let elapsed = Self.clock.now - failure.lastAttempt
            guard NowPlayingArtworkRetryPolicy.shouldAttempt(
                afterAttempts: failure.attempts,
                elapsed: elapsed
            ) else { return }
        }

        let transport = self.transport
        artworkFetches[url] = Task { [weak self] in
            let data = try? await Self.artworkData(for: url, transport: transport)
            guard Task.isCancelled == false, let self else { return }
            self.artworkFetches[url] = nil
            if let data {
                self.recordArtworkSuccess(data, for: url)
            } else {
                self.recordArtworkFailure(for: url)
            }
            // Re-run the decision: `url` is now advertisable either way, so a
            // held identity can move on instead of waiting for the next update.
            if let lastPush = self.lastPush {
                self.apply(lastPush)
            }
        }
    }

    private func recordArtworkSuccess(_ data: Data, for url: URL) {
        if artworkFailures.removeValue(forKey: url) != nil {
            // It failed before it worked, so the framework has a failure latched
            // against this URL's plain identity. Mark it so the id moves.
            recoveredArtwork.insert(url)
        }
        storeResidentArtwork(data, for: url)
    }

    private func recordArtworkFailure(for url: URL) {
        if artworkFailures[url] == nil, artworkFailures.count >= Self.maxArtworkFailureURLs {
            artworkFailures.removeAll()
        }
        var failure = artworkFailures[url] ?? ArtworkFailure(attempts: 0, lastAttempt: Self.clock.now)
        failure.attempts += 1
        failure.lastAttempt = Self.clock.now
        artworkFailures[url] = failure
    }

    func storeResidentArtwork(_ data: Data, for url: URL) {
        if residentArtwork[url] == nil {
            residentOrder.append(url)
        }
        residentArtwork[url] = data
        while residentOrder.count > Self.residentArtworkCapacity {
            let evicted = residentOrder.removeFirst()
            // Never evict what is on screen; the provider for it is a memory
            // hand-off and would otherwise silently become a network fetch.
            guard evicted != presentedArtworkURL else {
                residentOrder.append(evicted)
                continue
            }
            residentArtwork.removeValue(forKey: evicted)
        }
    }

    /// Downloads `url` and returns bytes `ArtworkRepresentation` accepts,
    /// normalizing when it doesn't or when the payload is oversized. Returns the
    /// bytes rather than the representation so the result can be cached and handed
    /// to a `@Sendable` provider closure; rebuilding the representation from
    /// resident bytes is local work, which is the whole point.
    nonisolated static func artworkData(
        for url: URL,
        transport: any HTTPTransporting
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = artworkCachePolicy
        let data = try await transport.data(for: request)
        if data.count <= maxPassthroughArtworkBytes, (try? ArtworkRepresentation(data: data)) != nil {
            return data
        }
        guard let normalized = normalizedArtworkData(from: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        // Fail here rather than inside the provider, so a payload we can't turn
        // into artwork is recorded as a failure instead of being advertised.
        _ = try ArtworkRepresentation(data: normalized)
        return normalized
    }

    /// Some remote album-art payloads decode fine in ImageIO but are rejected by
    /// `ArtworkRepresentation(data:)`, and some station favicons are far larger
    /// than any now-playing surface needs. Normalize through a downsampling decode
    /// + re-encode. 600 px matches what the iTunes lookup asks for and comfortably
    /// covers the lock-screen tile; PNG rather than JPEG because favicons routinely
    /// carry transparency that JPEG would flatten to black.
    nonisolated static func normalizedArtworkData(from data: Data) -> Data? {
        ImageIODownsampler.encode(data, maxPixelSize: 600, outputType: .png)
    }
}

#endif
