import Foundation
import Observation
import RadioDirectory

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

    /// Invoked whenever a station is chosen for playback. The app layer uses this
    /// to log recents so Playback does not depend on the persistence layer.
    /// (An event hook, deliberately — `state`/`nowPlaying` are @Observable and
    /// consumers follow them with `Observations`; a play is a discrete action.)
    @ObservationIgnored public var onStationPlayed: ((Station) -> Void)?

    /// Resolves album art for a track. Injected by the app layer so the
    /// Playback package stays free of any artwork/UI dependency. The closure
    /// runs on the main actor (hop off it internally for network work) and
    /// should return `nil` on failure or when the feature is disabled.
    /// Called once per unique track change.
    @ObservationIgnored public var albumArtURLProvider: (@MainActor (AudioTrackInfo) async -> URL?)?

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
        outputStarted = false
        resumeAfterInterruption = false
        nowPlayingCenter.clear()
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
