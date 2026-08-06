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

/// A track the listener heard on a station, handed to the app layer's local
/// listening-history log. Emitted at parse time (before any Apple Music link
/// is known) and again once resource resolution attaches one.
public struct HeardTrack {
    public let station: Station
    public let track: NowPlayingMetadata
    public let appleMusicURL: URL?

    public init(station: Station, track: NowPlayingMetadata, appleMusicURL: URL?) {
        self.station = station
        self.track = track
        self.appleMusicURL = appleMusicURL
    }
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

    /// Invoked whenever a station is chosen for playback. The app layer uses this
    /// to log recents so Playback does not depend on the persistence layer.
    /// (An event hook, deliberately — `state`/`nowPlaying` are @Observable and
    /// consumers follow them with `Observations`; a play is a discrete action.)
    @ObservationIgnored public var onStationPlayed: ((Station) -> Void)?

    /// Invoked when parsed now-playing track metadata is received for the active
    /// station (and again when Apple Music resolution completes for that track).
    /// The app layer uses this to persist local listening history.
    @ObservationIgnored public var onTrackHeard: ((HeardTrack) -> Void)?

    /// Resolves supplemental resources (album art + Apple Music link) for a
    /// track. Injected by the app layer so the Playback package stays free of
    /// any artwork/UI dependency. The closure runs on the main actor (hop off
    /// it internally for network work) and should return ``TrackResources/none``
    /// on failure or when the feature is disabled. Called once per unique track
    /// change.
    @ObservationIgnored public var trackResourcesProvider: (@MainActor (AudioTrackInfo) async -> TrackResources)?
    @ObservationIgnored public var tapToAudioPrewarmEnabledProvider: (@MainActor () -> Bool) = { false }

    public var currentStation: Station? { activeStation }

    /// Whether the active ``AudioOutput`` can apply an ``EqualizerPreset``.
    /// `false` for engines with no supported way to insert a filter into their
    /// render chain (`AVPlayer`-backed engines, and any ``AudioOutput`` test
    /// double that isn't also a ``RadioPlaybackEngine``) — settings UI should
    /// hide the equalizer control entirely rather than show one that does
    /// nothing.
    public var supportsEqualizer: Bool {
        (output as? any RadioPlaybackEngine)?.supportsEqualizer ?? false
    }

    /// Applies `preset` to the active output's equalizer, if it has one. A
    /// no-op when ``supportsEqualizer`` is `false`.
    public func setEqualizerPreset(_ preset: EqualizerPreset) {
        (output as? any RadioPlaybackEngine)?.setEqualizerPreset(preset)
    }

    /// Applies the persisted preset the user last chose, given its stored raw
    /// value. Ignores a value that no longer maps to a case, which is what a
    /// preset removed in a later release leaves behind in `UserDefaults`.
    public func restoreEqualizerPreset(rawValue: Int) {
        guard let preset = EqualizerPreset(rawValue: rawValue) else { return }
        setEqualizerPreset(preset)
    }

    // These are `internal` rather than `private` because the wiring lives in a
    // sibling extension file (PlaybackController+Internals.swift); nothing here
    // is part of the public API.
    @ObservationIgnored var activeStation: Station?
    @ObservationIgnored let directory: any RadioDirectoryProviding
    @ObservationIgnored let output: any AudioOutput
    @ObservationIgnored let nowPlayingCenter: any NowPlayingPresenting
    @ObservationIgnored var resolveTask: Task<Void, Never>?
    @ObservationIgnored var albumArtTask: Task<Void, Never>?

    /// The last endpoint resolved for `activeStation`, reused across reconnect
    /// attempts so a flaky stream doesn't re-run resolution (a `.pls` fetch +
    /// parse for SHOUTcast, a `byuuid` round-trip for a Radio-Browser station
    /// that lost its snapshot URL) on every backoff. Cleared on a fresh
    /// ``play(_:)`` so a genuinely new choice always re-resolves.
    @ObservationIgnored var resolvedEndpoint: StreamEndpoint?

    /// Battery hygiene windows (see the schedule methods below). Both are
    /// injectable so tests can use short values; there is deliberately no
    /// user-facing setting — this is invisible housekeeping.
    @ObservationIgnored let pausedReleaseTimeout: Duration
    @ObservationIgnored let pausedReleaseTimer = OneShotTimer()
    @ObservationIgnored let stallTimeout: Duration
    @ObservationIgnored let stallCeilingTimer = OneShotTimer()

    /// How long a resume may go unacknowledged before the stream is rejoined
    /// (see ``scheduleResumeWatchdog(for:)``). Injectable so tests don't wait
    /// seconds; no user-facing setting.
    @ObservationIgnored let resumeWatchdogTimeout: Duration
    @ObservationIgnored let resumeWatchdogTimer = OneShotTimer()

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
    @ObservationIgnored var tapToAudioTrace: TapToAudioLatencyTrace?

    /// Whether `output.start` has run for the active station. False while the
    /// stream endpoint is still resolving, or after a pause during loading —
    /// in that case `resume()` must re-play rather than resume a nonexistent player.
    @ObservationIgnored var outputStarted = false
    @ObservationIgnored var activeStreamGeneration: UInt64 = 0

    /// Set when the system interrupts playback that was active, so playback can
    /// resume automatically when the interruption ends. Armed per interruption
    /// (see ``handleInterruptionBegan(station:)``) — never left set across one.
    @ObservationIgnored var resumeAfterInterruption = false
    /// Held only when an active route loss paused this controller's playback.
    @ObservationIgnored var resumeAfterRouteChange = false

    /// Whether an interruption that ends *without* the system's resume hint may
    /// still resume playback, which holds only for the window below (see
    /// ``handleInterruptionEnded(shouldResume:otherAudioIsPlaying:)``).
    @ObservationIgnored var mayResumeWithoutSystemHint = false

    /// How long after an interruption begins a hintless end may still resume.
    /// Long enough to cover a call, an alarm, or a Siri exchange; short enough
    /// that a listener who moved on to another app for a while isn't surprised by
    /// radio starting itself. Injectable like the other windows; no user setting.
    @ObservationIgnored let hintlessResumeWindow: Duration
    @ObservationIgnored let hintlessResumeWindowTimer = OneShotTimer()

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
        reconnectBaseDelay: Duration = .seconds(2),
        resumeWatchdogTimeout: Duration = .seconds(2),
        hintlessResumeWindow: Duration = .seconds(90)
    ) {
        self.directory = directory
        self.output = output
        self.nowPlayingCenter = nowPlayingCenter
        self.pausedReleaseTimeout = pausedReleaseTimeout
        self.stallTimeout = stallTimeout
        self.maxReconnectAttempts = maxReconnectAttempts
        self.reconnectBaseDelay = reconnectBaseDelay
        self.resumeWatchdogTimeout = resumeWatchdogTimeout
        self.hintlessResumeWindow = hintlessResumeWindow

        configureOutput()
        configureRemoteCommands()
    }

    // MARK: - Intents

    public func play(_ station: Station) {
        reconnectAttempts = 0
        tapToAudioTrace?.cancel()
        tapToAudioTrace = TapToAudioLatencyTrace(
            stationID: station.id,
            prewarmEnabled: tapToAudioPrewarmEnabledProvider()
        )
        // A fresh choice always re-resolves; the cache exists only to spare
        // reconnect attempts from repeating resolution for the same station.
        resolvedEndpoint = nil
        startPlayback(of: station)
        onStationPlayed?(station)
    }

    public func pause() {
        resumeAfterRouteChange = false
        // A user pause must win over a pending auto-reconnect, or a stream the
        // user just stopped would resurrect itself when the reconnect fires.
        reconnectTimer.cancel()
        // Likewise over a resume that is still waiting to be acknowledged: the
        // watchdog would otherwise rejoin a stream the user just paused.
        resumeWatchdogTimer.cancel()
        // Likewise it must win over a pending interruption auto-resume: pausing
        // during a phone call means "stay paused" when the call ends.
        disarmInterruptionResume()
        // Pausing while the stream endpoint is still resolving must cancel the
        // pending start, or audio would begin after the user asked it not to.
        if case let .loading(station) = state {
            resolveTask?.cancel()
            tapToAudioTrace?.cancel()
            tapToAudioTrace = nil
            state = .paused(station)
            nowPlayingCenter.update(
                station: station,
                track: nowPlaying,
                isPlaying: false,
                artwork: .resolved(albumArtURL)
            )
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
                // Armed before the call, so an output that acknowledges the
                // resume synchronously cancels the watchdog rather than racing
                // it (see `scheduleResumeWatchdog(for:)`).
                scheduleResumeWatchdog(for: station)
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
        tapToAudioTrace?.cancel()
        tapToAudioTrace = nil
        resolveTask?.cancel()
        albumArtTask?.cancel()
        albumArtTask = nil
        pausedReleaseTimer.cancel()
        stallCeilingTimer.cancel()
        reconnectTimer.cancel()
        resumeWatchdogTimer.cancel()
        reconnectAttempts = 0
        resumeAfterRouteChange = false
        output.stop()
        activeStation = nil
        state = .idle
        nowPlaying = nil
        albumArtURL = nil
        appleMusicURL = nil
        outputStarted = false
        disarmInterruptionResume()
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
        case let .failed(error):
            return .failed(error)
        case .idle:
            return .idle
        }
    }
}
