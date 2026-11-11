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
            // more chance at an image rather than none — but only after a *network*
            // failure (2026-11-10). When the server itself answered with something
            // unusable (a maintenance page, an error status, undecodable bytes), the
            // system fetching it again can't succeed, and a lazy provider re-downloads
            // on every system artwork request: a macOS media widget polling every five
            // seconds turned one dead station favicon into a fetch-and-decode-failure
            // loop that bypassed the retry backoff. Those retries go through
            // `fetchArtworkIfNeeded` on a timer, and a recovery moves the content id
            // ("#r") so the system pulls the resident bytes.
            if artworkFailures[url]?.serverRejected == true {
                return nil
            }
            let transport = self.transport
            return Artwork(id: url.absoluteString) { @Sendable _ in
                let data = try await Self.artworkData(for: url, transport: transport)
                return try ArtworkRepresentation(data: data)
            }
        }

        func fetchArtworkIfNeeded(_ url: URL) {
            guard residentArtwork[url] == nil, artworkFetches[url] == nil else { return }
            if let failure = artworkFailures[url] {
                let elapsed = Self.clock.now - failure.lastAttempt
                guard NowPlayingArtworkRetryPolicy.shouldAttempt(
                    afterAttempts: failure.attempts,
                    elapsed: elapsed,
                ) else { return }
            }

            let transport = self.transport
            artworkFetches[url] = Task { [weak self] in
                let result: Result<Data, any Error>
                do {
                    result = try await .success(Self.artworkData(for: url, transport: transport))
                } catch {
                    result = .failure(error)
                }
                guard Task.isCancelled == false, let self else { return }
                self.artworkFetches[url] = nil
                switch result {
                case let .success(data):
                    self.recordArtworkSuccess(data, for: url)
                case let .failure(error):
                    self.recordArtworkFailure(for: url, serverRejected: Self.isServerRejection(error))
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

        /// The server responded, but not with artwork — as opposed to the request
        /// never completing (offline, timeout, a tunnel).
        nonisolated static func isServerRejection(_ error: any Error) -> Bool {
            switch error {
            case HTTPTransportError.httpStatus, HTTPTransportError.invalidResponse:
                true
            case HTTPTransportError.transport, is CancellationError:
                false
            case let error as URLError:
                // Our own "not artwork" verdict; every other URLError is the network.
                error.code == .cannotDecodeContentData
            default:
                // ArtworkRepresentation refusing bytes we already downloaded.
                true
            }
        }

        private func recordArtworkFailure(for url: URL, serverRejected: Bool) {
            // Evict the single least-recently-failed entry rather than clearing the
            // table. Wiping it would reset every attempt count, so a persistently
            // dead URL could exceed `maximumAttempts` in one session whenever enough
            // unique track-art URLs failed to fill the table — which is exactly the
            // unbounded retrying the cap exists to prevent.
            if artworkFailures[url] == nil, artworkFailures.count >= Self.maxArtworkFailureURLs,
               let oldest = artworkFailures.min(by: { $0.value.lastAttempt < $1.value.lastAttempt })?.key {
                artworkFailures.removeValue(forKey: oldest)
            }
            var failure = artworkFailures[url] ?? ArtworkFailure(attempts: 0, lastAttempt: Self.clock.now)
            failure.attempts += 1
            failure.lastAttempt = Self.clock.now
            failure.serverRejected = serverRejected
            artworkFailures[url] = failure
            scheduleArtworkRetry(for: url, afterAttempts: failure.attempts)
        }

        /// Runs the next backoff attempt on a timer rather than waiting for the next
        /// push. Retries used to happen only when `apply` ran again, which for a
        /// station that sends no track titles (KEXP's stream, for one) is effectively
        /// never — so artwork that came back mid-session stayed missing until a
        /// restart. Bounded by `NowPlayingArtworkRetryPolicy.maximumAttempts`, and
        /// skipped once the URL is no longer what this session is showing or waiting on.
        private func scheduleArtworkRetry(for url: URL, afterAttempts attempts: Int) {
            guard attempts < NowPlayingArtworkRetryPolicy.maximumAttempts else { return }
            let delay = NowPlayingArtworkRetryPolicy.retryDelay(afterAttempts: attempts)
            Task { [weak self] in
                try? await Task.sleep(for: delay, clock: Self.clock)
                guard Task.isCancelled == false, let self, let lastPush = self.lastPush else { return }
                // `clear()` wipes the failure table; nothing to retry after a stop.
                guard self.artworkFailures[url] != nil else { return }
                let wanted = lastPush.station.artworkURL == url || self.presentedArtworkURL == url
                    || lastPush.artwork == .resolved(url)
                guard wanted else { return }
                self.fetchArtworkIfNeeded(url)
            }
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
            transport: any HTTPTransporting,
        ) async throws -> Data {
            var request = URLRequest(url: url)
            request.cachePolicy = artworkCachePolicy
            // A maintenance or parking page answering 200 on the image path throws
            // here, and is recorded and retried with backoff like any other failure
            // rather than handed to ImageIO (see `ImagePayload`).
            let data = try await transport.imageData(for: request)
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
