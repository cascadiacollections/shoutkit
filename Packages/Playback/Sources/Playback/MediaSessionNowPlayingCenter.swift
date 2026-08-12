#if canImport(NowPlaying)

import Foundation
import ImageIODownsample
import NowPlaying
import Observation
import RadioDirectory

/// iOS 27+ implementation of ``NowPlayingPresenting`` on the NowPlaying
/// framework — the WWDC26 replacement for the `MPNowPlayingInfoCenter`
/// dictionary + `MPRemoteCommandCenter` global-singleton pattern that
/// ``NowPlayingCenter`` bridges. A typed, observable `MediaSession` carries
/// `RadioContent` (purpose-built for live radio: station name, program line,
/// `duration: .live`) and structured `MediaCommand`s.
///
/// The framework pulls artwork through an async `Artwork` provider. That is the
/// right shape for the lock screen, which can wait, and the wrong shape for
/// Bluetooth: over AVRCP a head unit is told the track changed and then fetches
/// cover art on a separate, slow channel, so a provider that only *starts* a
/// network download when asked leaves the car with nothing to show — it keeps the
/// last image it successfully fetched, which after launch is the previous app's.
/// This class therefore materializes artwork bytes *before* advertising the
/// content identity that carries them; the provider is a hand-off from memory in
/// the steady state. See ``NowPlayingArtwork`` for the other half of the fix.
///
/// Selected at runtime by ``PlaybackController``'s production initializer;
/// iOS 26 devices keep the legacy `MediaPlayer` path.
///
/// `watchOS 27` is named explicitly rather than left to the `*` wildcard. While
/// the watchOS floor was 27 the wildcard was equivalent — it means "available
/// from this platform's deployment target", and that target was 27. Dropping the
/// floor to 26 (DECISIONS.md 2026-08-12) made the two differ: the wildcard then
/// claimed availability from watchOS 26, while every `NowPlaying` symbol this
/// type touches is watchOS 27+, and the watch build failed with six errors.
@available(iOS 27, macOS 27, watchOS 27, *)
@MainActor
public final class MediaSessionNowPlayingCenter: NowPlayingPresenting {
    public var onPlay: (() -> Void)?
    public var onPause: (() -> Void)?
    public var onStop: (() -> Void)?
    public var onToggle: (() -> Void)?

    /// The observable contract the system watches: content, playback snapshot,
    /// and available commands. `MediaSession` tracks changes via Observation.
    @Observable
    @MainActor
    final class SessionState: MediaSessionRepresentable {
        let id = "com.cascadiacollections.shoutkit.playback"
        var content: (any MediaContentRepresentable)?
        var playbackSnapshot: MediaPlaybackSnapshot?
        var commands: [MediaCommand] = []
    }

    /// The last `update(...)`, replayed when a background artwork fetch lands so
    /// the content identity can flip to artwork whose bytes we now hold.
    private struct Push {
        let station: Station
        let track: NowPlayingMetadata?
        let isPlaying: Bool
        let artwork: NowPlayingArtwork
    }

    /// What was last written to `state.content`, so a replay that changes nothing
    /// the system can see doesn't churn an Observation-tracked property. Artwork
    /// residency deliberately isn't part of it: the framework has already latched
    /// whatever it resolved for an id, so re-offering a memory-backed provider
    /// under the same id would be a notification with nothing behind it.
    private struct AppliedContent: Equatable {
        let contentID: String
        let stationName: String
        let programName: String?
        let genre: String?
    }

    private let state = SessionState()
    private var session: MediaSession<SessionState>?
    private let transport: any HTTPTransporting

    /// Materialized artwork bytes keyed by source URL — validated (and normalized
    /// where needed) so building an `ArtworkRepresentation` from them is local
    /// work that can't fail on the network. Bytes rather than the representation
    /// itself because `ArtworkRepresentation` is not `Sendable`, so it can neither
    /// be cached across isolation nor captured by the provider's `@Sendable`
    /// closure. Small and bounded: a session cycles through the station's own art
    /// plus the current track's, and this stays resident while backgrounded, which
    /// is exactly when jetsam hunts.
    private var residentArtwork: [URL: Data] = [:]
    private var residentOrder: [URL] = []

    /// URLs whose fetch already failed. Treated as advertisable so a URL we can't
    /// download can't pin a previous track's image on screen forever; the system
    /// is free to try the lazy provider itself.
    private var unavailableArtwork: Set<URL> = []

    private var artworkFetches: [URL: Task<Void, Never>] = [:]

    private var presentedArtworkURL: URL?
    private var presentedStationID: String?
    private var lastPush: Push?
    private var appliedContent: AppliedContent?

    /// Four covers the working set (station art + current track + the track being
    /// fetched) with room to spare, and bounds what a backgrounded session pins.
    private nonisolated static let residentArtworkCapacity = 4

    /// Artwork URLs are content-addressed — iTunes serves one `…600x600bb.jpg` per
    /// album and station favicons are stable — so a forced revalidation buys
    /// freshness nobody can perceive while putting a network round-trip in front of
    /// every cover-art request. (`NowPlayingCenter` keeps
    /// `.reloadRevalidatingCacheData`: it re-fetches once per station switch, not
    /// once per surface request.)
    private nonisolated static let artworkCachePolicy: URLRequest.CachePolicy = .returnCacheDataElseLoad

    /// Above this, re-encode rather than hand the payload over untouched. A 3 MB
    /// station favicon is a slow Bluetooth cover-art transfer for no visible gain;
    /// typical 600 px album art (~60 KB) passes through as-is.
    private nonisolated static let maxPassthroughArtworkBytes = 512 * 1024

    private nonisolated static let maxUnavailableArtworkURLs = 64

    public init(transport: any HTTPTransporting = URLSessionHTTPTransport.shared) {
        self.transport = transport
    }

    public func update(station: Station, track: NowPlayingMetadata?, isPlaying: Bool, artwork: NowPlayingArtwork) {
        let push = Push(station: station, track: track, isPlaying: isPlaying, artwork: artwork)
        lastPush = push
        apply(push)
    }

    public func clear() {
        lastPush = nil
        appliedContent = nil
        presentedArtworkURL = nil
        presentedStationID = nil
        for (_, task) in artworkFetches {
            task.cancel()
        }
        artworkFetches.removeAll()
        // Resident bytes survive a stop — replaying the same station shouldn't
        // re-download — but a failed fetch must be retryable on the next play.
        unavailableArtwork.removeAll()
        state.content = nil
        state.playbackSnapshot = MediaPlaybackSnapshot(state: .stopped)
        // Dropping the session invalidates it and removes the entry from the
        // system surface; the next update() creates a fresh one.
        session = nil
    }

    // MARK: - Content

    private func apply(_ push: Push) {
        if session == nil {
            state.commands = makeCommands()
            session = MediaSession(state)
        }

        let decision = NowPlayingArtworkPolicy.decide(
            artwork: push.artwork,
            stationArtworkURL: push.station.artworkURL,
            presented: presentedArtworkURL,
            isSameStation: presentedStationID == push.station.id,
            readyArtworkURLs: readyArtworkURLs
        )

        let advertised: URL?
        switch decision {
        case let .present(url):
            advertised = url
        case let .hold(current, pending):
            advertised = current
            fetchArtworkIfNeeded(pending)
        }
        if let advertised {
            fetchArtworkIfNeeded(advertised)
        }

        presentedArtworkURL = advertised
        presentedStationID = push.station.id

        // The framework latches the first artwork it resolves for a given content
        // id and never re-pulls `Artwork` for that id again — with a station-stable
        // id the station art pushed at track start won for the whole session
        // (verified on-device: the system requested bytes for the station URL but
        // never for the later album-art URL). Folding the artwork identity into the
        // id makes each distinct artwork new content the framework refreshes.
        // `duration: .live` means no scrubber position is lost when it changes.
        //
        // That makes every identity change a track-changed notification on
        // Bluetooth, which is why `advertised` only moves to artwork we already
        // hold: one change per track, with the image ready behind it.
        let contentID = advertised.map { "\(push.station.id)#\($0.absoluteString)" } ?? push.station.id
        let genre = push.station.genre.isEmpty ? nil : push.station.genre
        let applied = AppliedContent(
            contentID: contentID,
            stationName: push.station.name,
            programName: programName(for: push.track),
            genre: genre
        )

        if applied != appliedContent {
            var content = RadioContent(
                id: applied.contentID,
                stationName: applied.stationName,
                programName: applied.programName,
                artwork: artwork(for: advertised)
            )
            content.genre = applied.genre
            state.content = content
            appliedContent = applied
        }

        state.playbackSnapshot = MediaPlaybackSnapshot(state: push.isPlaying ? .playing() : .paused)

        if push.isPlaying, let session, session.isApplicationPrimary == false {
            // Best effort: becoming primary improves command routing, but playback
            // remains functional if the system declines this request.
            Task { try? await session.requestToBecomeApplicationPrimary() }
        }
    }

    /// "Title — Artist" as the program line under the station name.
    private func programName(for track: NowPlayingMetadata?) -> String? {
        let program = [track?.title, track?.artist].compactMap(\.self).joined(separator: " — ")
        return program.isEmpty ? nil : program
    }

    // MARK: - Artwork

    private var readyArtworkURLs: Set<URL> {
        Set(residentArtwork.keys).union(unavailableArtwork)
    }

    /// Hands the system an `Artwork` for `url`. Once the bytes are resident the
    /// provider answers from memory, so nothing stands between the track-changed
    /// notification and the head unit's cover-art request.
    private func artwork(for url: URL?) -> Artwork? {
        guard let url else { return nil }
        if let residentData = residentArtwork[url] {
            return Artwork(id: url.absoluteString) { @Sendable _ in
                try ArtworkRepresentation(data: residentData)
            }
        }
        // Not resident yet (first play, or a fetch that failed): keep the lazy
        // provider so the lock screen still gets an image.
        let transport = self.transport
        return Artwork(id: url.absoluteString) { @Sendable _ in
            let data = try await Self.artworkData(for: url, transport: transport)
            return try ArtworkRepresentation(data: data)
        }
    }

    private func fetchArtworkIfNeeded(_ url: URL) {
        guard residentArtwork[url] == nil else { return }
        guard unavailableArtwork.contains(url) == false else { return }
        guard artworkFetches[url] == nil else { return }

        let transport = self.transport
        artworkFetches[url] = Task { [weak self] in
            let data = try? await Self.artworkData(for: url, transport: transport)
            guard Task.isCancelled == false, let self else { return }
            self.artworkFetches[url] = nil
            if let data {
                self.storeResidentArtwork(data, for: url)
            } else {
                // Bounded: a long drive over a bad link must not accumulate every
                // URL it failed. Dropping the whole set just re-arms the retries.
                if self.unavailableArtwork.count >= Self.maxUnavailableArtworkURLs {
                    self.unavailableArtwork.removeAll()
                }
                self.unavailableArtwork.insert(url)
            }
            // Re-run the decision: `url` is now advertisable either way, so a
            // held identity can move on instead of waiting for the next update.
            if let lastPush = self.lastPush {
                self.apply(lastPush)
            }
        }
    }

    private func storeResidentArtwork(_ data: Data, for url: URL) {
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
    private nonisolated static func artworkData(
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
        // into artwork is recorded as unavailable instead of being advertised.
        _ = try ArtworkRepresentation(data: normalized)
        return normalized
    }

    /// Some remote album-art payloads decode fine in ImageIO but are rejected by
    /// `ArtworkRepresentation(data:)`, and some station favicons are far larger
    /// than any now-playing surface needs. Normalize through a downsampling decode
    /// + re-encode. 600 px matches what the iTunes lookup asks for and comfortably
    /// covers the lock-screen tile; PNG rather than JPEG because favicons routinely
    /// carry transparency that JPEG would flatten to black.
    private nonisolated static func normalizedArtworkData(from data: Data) -> Data? {
        ImageIODownsampler.encode(data, maxPixelSize: 600, outputType: .png)
    }

    // MARK: - Commands

    /// Command callbacks arrive on arbitrary executors; hop to the main actor
    /// before touching the controller-facing closures.
    private func makeCommands() -> [MediaCommand] {
        [
            .play { [weak self] in await MainActor.run { self?.onPlay?() } },
            .pause { [weak self] in await MainActor.run { self?.onPause?() } },
            .stop { [weak self] in await MainActor.run { self?.onStop?() } },
            .togglePlayPause { [weak self] in await MainActor.run { self?.onToggle?() } },
        ]
    }
}

#endif
