import Foundation
import Observation
import RadioDirectory

/// Supplemental, best-effort resources resolved for a track from an external
/// catalog: album artwork and a link to open the track in Apple Music. Both
/// are independently optional — a lookup may yield one, both, or neither.
public struct TrackResources: Sendable, Equatable {
    public var artworkURL: URL?
    public var appleMusicURL: URL?

    public init(artworkURL: URL? = nil, appleMusicURL: URL? = nil) {
        self.artworkURL = artworkURL
        self.appleMusicURL = appleMusicURL
    }

    /// No resources — the value returned when a lookup fails or is disabled.
    public static let none = TrackResources()
}

/// App-wide, observable playback state. Injected through the SwiftUI environment so
/// the mini-player, Now Playing screen, and every station row read and drive the same
/// playback. Owns the ``AudioOutput`` and mirrors its status into ``PlaybackState``.
@MainActor
@Observable
public final class PlaybackController {
    // `internal(set)` (not `private(set)`) so the wiring extension in
    // PlaybackController+Internals.swift can drive these; the public read
    // surface is unchanged.
    public internal(set) var state: PlaybackState = .idle

    public internal(set) var nowPlaying: NowPlayingMetadata?

    /// The resolved album art URL for the current track, or `nil` when no
    /// track metadata is available, the lookup is still in progress, or the
    /// lookup returned no result. Consumers fall back to the station's own
    /// artwork URL when this is `nil`.
    public internal(set) var albumArtURL: URL?

    /// A link that opens the current track in Apple Music, or `nil` when no
    /// track metadata is available, the lookup is still in progress, or the
    /// catalog has no page for it. Follows the same lifecycle as
    /// ``albumArtURL``: cleared on a track change, a fresh start, and stop, but
    /// preserved across an automatic reconnect so the last-known link stays
    /// available while the stream re-buffers (ICY repopulates it on success).
    public internal(set) var appleMusicURL: URL?

    /// Whether the active station is currently in a detected ad break. Set by
    /// the ICY track-info handler (in PlaybackController+Internals.swift) and
    /// gates the ambient-fallback offer, so it is `internal(set)` while staying
    /// publicly readable.
    public internal(set) var isAdPlaying = false

    /// Whether an ambient-fallback station lookup is in flight, so the UI can
    /// show a spinner on the offer button.
    public internal(set) var isLoadingAmbientFallback = false

    /// A user-facing message when the last ambient-fallback lookup found no
    /// station, or `nil` when there is nothing to report.
    public internal(set) var ambientFallbackError: String?

    /// Invoked whenever a station is chosen for playback. The app layer uses this
    /// to log recents so Playback does not depend on the persistence layer.
    /// (An event hook, deliberately — `state`/`nowPlaying` are @Observable and
    /// consumers follow them with `Observations`; a play is a discrete action.)
    @ObservationIgnored public var onStationPlayed: ((Station) -> Void)?

    /// Resolves supplemental resources (album art + Apple Music link) for a
    /// track. Injected by the app layer so the Playback package stays free of
    /// any artwork/UI dependency. The closure runs on the main actor (hop off
    /// it internally for network work) and should return ``TrackResources/none``
    /// on failure or when the feature is disabled. Called once per unique track
    /// change.
    @ObservationIgnored public var trackResourcesProvider: (@MainActor (AudioTrackInfo) async -> TrackResources)?

    public var currentStation: Station? { activeStation }

    // These are `internal` rather than `private` because the wiring lives in a
    // sibling extension file (PlaybackController+Internals.swift); nothing here
    // is part of the public API.
    @ObservationIgnored var activeStation: Station?
    @ObservationIgnored let directory: any RadioDirectoryProviding
    @ObservationIgnored let output: any AudioOutput
    @ObservationIgnored let nowPlayingCenter: any NowPlayingPresenting
    @ObservationIgnored var resolveTask: Task<Void, Never>?
    @ObservationIgnored var albumArtTask: Task<Void, Never>?

    /// Battery hygiene windows (see the schedule methods below). Both are
    /// injectable so tests can use short values; there is deliberately no
    /// user-facing setting — this is invisible housekeeping.
    @ObservationIgnored let pausedReleaseTimeout: Duration
    @ObservationIgnored let pausedReleaseTimer = OneShotTimer()
    @ObservationIgnored let stallTimeout: Duration
    @ObservationIgnored let stallCeilingTimer = OneShotTimer()

    /// Bounded automatic reconnect (see ``attemptReconnect(for:fallback:)``).
    /// A stall or a mid-play failure retries the stream a few times on a
    /// backed-off schedule before surfacing a terminal state — network radio
    /// drops for transient reasons (tunnel, cell handoff) far more often than
    /// permanent ones. Both knobs are injectable so tests can use a short delay
    /// and small budget; there is no user-facing setting.
    @ObservationIgnored let maxReconnectAttempts: Int
    @ObservationIgnored let reconnectBaseDelay: Duration
    @ObservationIgnored let reconnectTimer = OneShotTimer()
    @ObservationIgnored var reconnectAttempts = 0

    /// Whether `output.start` has run for the active station. False while the
    /// stream endpoint is still resolving, or after a pause during loading —
    /// in that case `resume()` must re-play rather than resume a nonexistent player.
    @ObservationIgnored var outputStarted = false

    /// Set when the system interrupts playback that was active, so playback can
    /// resume automatically when the interruption ends with a resume hint.
    @ObservationIgnored var resumeAfterInterruption = false

    /// Designated initializer with every collaborator explicit — what tests use.
    /// The iOS production defaults live in the convenience initializer (in
    /// PlaybackControllerPlatform.swift) so this type (and its tests) build on
    /// platforms without AVAudioSession/UIKit.
    public init(
        directory: any RadioDirectoryProviding,
        output: any AudioOutput,
        nowPlayingCenter: any NowPlayingPresenting,
        pausedReleaseTimeout: Duration = .seconds(10 * 60),
        stallTimeout: Duration = .seconds(90),
        maxReconnectAttempts: Int = 3,
        reconnectBaseDelay: Duration = .seconds(2)
    ) {
        self.directory = directory
        self.output = output
        self.nowPlayingCenter = nowPlayingCenter
        self.pausedReleaseTimeout = pausedReleaseTimeout
        self.stallTimeout = stallTimeout
        self.maxReconnectAttempts = maxReconnectAttempts
        self.reconnectBaseDelay = reconnectBaseDelay

        configureOutput()
        configureRemoteCommands()
    }

    // MARK: - Intents

    public func play(_ station: Station) {
        reconnectAttempts = 0
        startPlayback(of: station)
        onStationPlayed?(station)
    }

    public func pause() {
        // A user pause must win over a pending auto-reconnect, or a stream the
        // user just stopped would resurrect itself when the reconnect fires.
        reconnectTimer.cancel()
        // Likewise it must win over a pending interruption auto-resume: pausing
        // during a phone call means "stay paused" when the call ends.
        resumeAfterInterruption = false
        // Pausing while the stream endpoint is still resolving must cancel the
        // pending start, or audio would begin after the user asked it not to.
        if case let .loading(station) = state {
            resolveTask?.cancel()
            state = .paused(station)
            nowPlayingCenter.update(station: station, track: nowPlaying, isPlaying: false, artworkURL: albumArtURL)
            schedulePausedRelease()
            return
        }
        output.pause()
    }

    public func resume() {
        guard let station = activeStation else { return }

        switch state {
        case .paused:
            if outputStarted {
                pausedReleaseTimer.cancel()
                output.resume()
            } else {
                // Paused during loading, or the paused-release timeout tore
                // the player down: nothing to resume, so restart the stream.
                startPlayback(of: station)
            }
        case .failed:
            startPlayback(of: station)
        default:
            break
        }
    }

    /// Toggles play/pause for the currently active station.
    public func togglePlayPause() {
        switch state {
        case .playing, .buffering, .loading:
            pause()
        case .paused, .failed:
            resume()
        case .idle:
            break
        }
    }

    /// Plays the station if it isn't the active one; otherwise toggles play/pause.
    public func toggle(_ station: Station) {
        if activeStation?.id == station.id {
            togglePlayPause()
        } else {
            play(station)
        }
    }

    public func stop() {
        resolveTask?.cancel()
        albumArtTask?.cancel()
        albumArtTask = nil
        pausedReleaseTimer.cancel()
        stallCeilingTimer.cancel()
        reconnectTimer.cancel()
        reconnectAttempts = 0
        output.stop()
        activeStation = nil
        state = .idle
        nowPlaying = nil
        albumArtURL = nil
        appleMusicURL = nil
        isAdPlaying = false
        isLoadingAmbientFallback = false
        ambientFallbackError = nil
        outputStarted = false
        resumeAfterInterruption = false
        nowPlayingCenter.clear()
    }

    /// Offers a calm ambient station to play through the current ad break. Only
    /// acts while an ad is detected, and de-bounces concurrent taps. The lookup
    /// races user intent, so its result is discarded unless an ad is still
    /// playing on the same station when it returns — see the guard below.
    public func playAmbientFallback() async {
        guard isAdPlaying, isLoadingAmbientFallback == false else { return }

        isLoadingAmbientFallback = true
        ambientFallbackError = nil
        let currentStationID = activeStation?.id
        let fallback = await AmbientFallbackFinder.findStation(in: directory, excluding: currentStationID)
        isLoadingAmbientFallback = false

        // The lookup raced user intent: if the ad break ended, playback was
        // stopped, or another station started while searching, keep that
        // outcome rather than hijacking it with the fallback.
        guard isAdPlaying, activeStation?.id == currentStationID else { return }

        guard let fallback else {
            ambientFallbackError = "No ambient stations are available right now."
            return
        }

        play(fallback)
    }

    // MARK: - Per-station phase

    public func phase(for station: Station) -> StationPlaybackPhase {
        guard activeStation?.id == station.id else { return .idle }

        switch state {
        case .loading, .buffering:
            return .loading
        case .playing:
            return .playing
        case .paused:
            return .paused
        case let .failed(message):
            return .failed(message)
        case .idle:
            return .idle
        }
    }
}
