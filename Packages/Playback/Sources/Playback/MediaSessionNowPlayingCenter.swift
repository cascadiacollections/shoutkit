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
/// Every platform is named explicitly rather than left to the `*` wildcard. While
/// the watchOS floor was 27 the wildcard was equivalent — it means "available
/// from this platform's deployment target", and that target was 27. Dropping the
/// floor to 26 (DECISIONS.md 2026-08-12) made the two differ: the wildcard then
/// claimed availability from watchOS 26, while every `NowPlaying` symbol this
/// type touches is watchOS 27+, and the watch build failed with six errors.
///
/// `tvOS 27` is named for the same reason, pre-emptively: this file is gated only on
/// `canImport(NowPlaying)`, so it compiles on any platform that has the framework,
/// and a tvOS floor of 26 would reproduce the watchOS failure exactly.
@available(iOS 27, macOS 27, tvOS 27, watchOS 27, *)
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
    struct Push {
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
    let transport: any HTTPTransporting

    /// Materialized artwork bytes keyed by source URL — validated (and normalized
    /// where needed) so building an `ArtworkRepresentation` from them is local
    /// work that can't fail on the network. Bytes rather than the representation
    /// itself because `ArtworkRepresentation` is not `Sendable`, so it can neither
    /// be cached across isolation nor captured by the provider's `@Sendable`
    /// closure. Small and bounded: a session cycles through the station's own art
    /// plus the current track's, and this stays resident while backgrounded, which
    /// is exactly when jetsam hunts.
    var residentArtwork: [URL: Data] = [:]
    var residentOrder: [URL] = []

    /// URLs whose fetch has failed, with how often and when last tried. Treated
    /// as advertisable so a URL we can't download can't pin a previous track's
    /// image on screen forever; the system is free to try the lazy provider
    /// itself. Unlike the flat `Set` this replaced, a failure here is a delay
    /// rather than a verdict — see ``NowPlayingArtworkRetryPolicy``.
    var artworkFailures: [URL: ArtworkFailure] = [:]

    /// URLs that failed at least once and then fetched successfully. Their
    /// content identity carries a marker so the flip to resident bytes reads as
    /// *new* content: the framework latches whatever it resolved for an id, and
    /// what it latched for these was a failure, so re-offering a memory-backed
    /// provider under the same id would change nothing on screen. A URL recovers
    /// at most once — after that its bytes are resident and never re-fetched — so
    /// the id stays stable thereafter.
    var recoveredArtwork: Set<URL> = []

    struct ArtworkFailure {
        var attempts: Int
        var lastAttempt: ContinuousClock.Instant
    }

    var artworkFetches: [URL: Task<Void, Never>] = [:]

    var presentedArtworkURL: URL?
    private var presentedStationID: String?
    var lastPush: Push?
    private var appliedContent: AppliedContent?

    /// Four covers the working set (station art + current track + the track being
    /// fetched) with room to spare, and bounds what a backgrounded session pins.
    nonisolated static let residentArtworkCapacity = 4

    /// One clock for the retry bookkeeping. `ContinuousClock` rather than a wall
    /// clock because backoff must survive the device sleeping and the user
    /// changing time zones mid-drive, neither of which should re-arm a retry.
    nonisolated static let clock = ContinuousClock()

    /// Artwork URLs are content-addressed — iTunes serves one `…600x600bb.jpg` per
    /// album and station favicons are stable — so a forced revalidation buys
    /// freshness nobody can perceive while putting a network round-trip in front of
    /// every cover-art request. (`NowPlayingCenter` keeps
    /// `.reloadRevalidatingCacheData`: it re-fetches once per station switch, not
    /// once per surface request.)
    nonisolated static let artworkCachePolicy: URLRequest.CachePolicy = .returnCacheDataElseLoad

    /// Above this, re-encode rather than hand the payload over untouched. A 3 MB
    /// station favicon is a slow Bluetooth cover-art transfer for no visible gain;
    /// typical 600 px album art (~60 KB) passes through as-is.
    nonisolated static let maxPassthroughArtworkBytes = 512 * 1024

    /// Bounds what a long drive on a bad link can accumulate. Overflow evicts the
    /// least-recently-failed entry, one at a time, so each URL's attempt count
    /// survives — clearing the table wholesale would hand a dead URL a fresh set
    /// of retries every time the table filled.
    nonisolated static let maxArtworkFailureURLs = 64

    /// Defaults to `.nowPlayingArtwork`, not the in-app `.artwork` session.
    /// This class refuses to advertise artwork whose bytes it does not hold, so
    /// a deferred fetch is not a late image — it is no image at all, for the
    /// whole track. `.artwork`'s `.background` service type is precisely the
    /// tier the system defers behind a sustained audio stream, which is why
    /// this path gets its own (see
    /// `URLSessionHTTPTransport.nowPlayingArtworkConfiguration()`).
    public init(transport: any HTTPTransporting = URLSessionHTTPTransport.nowPlayingArtwork) {
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
        // `recoveredArtwork` survives alongside `residentArtwork` so a replayed
        // station keeps the identity its bytes were last advertised under.
        artworkFailures.removeAll()
        state.content = nil
        state.playbackSnapshot = MediaPlaybackSnapshot(state: .stopped)
        // Dropping the session invalidates it and removes the entry from the
        // system surface; the next update() creates a fresh one.
        session = nil
    }

    // MARK: - Content

    func apply(_ push: Push) {
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
        let contentID = advertised.map { url in
            // "#r" only for a URL that failed before it succeeded: the framework
            // latched that failure against the plain id, so the identity has to
            // move for it to pull the bytes we now hold.
            "\(push.station.id)#\(url.absoluteString)\(recoveredArtwork.contains(url) ? "#r" : "")"
        } ?? push.station.id
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
