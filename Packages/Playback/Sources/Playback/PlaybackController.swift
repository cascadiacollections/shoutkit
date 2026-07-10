import Foundation
import Observation
import RadioDirectory

/// App-wide, observable playback state. Injected through the SwiftUI environment so
/// the mini-player, Now Playing screen, and every station row read and drive the same
/// playback. Owns the ``AudioOutput`` and mirrors its status into ``PlaybackState``.
@MainActor
@Observable
public final class PlaybackController {
    public private(set) var state: PlaybackState = .idle

    public private(set) var nowPlaying: NowPlayingMetadata?

    /// The resolved album art URL for the current track, or `nil` when no
    /// track metadata is available, the lookup is still in progress, or the
    /// lookup returned no result. Consumers fall back to the station's own
    /// artwork URL when this is `nil`.
    public private(set) var albumArtURL: URL?

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

    @ObservationIgnored private var activeStation: Station?
    @ObservationIgnored private let directory: any RadioDirectoryProviding
    @ObservationIgnored private let output: any AudioOutput
    @ObservationIgnored private let nowPlayingCenter: any NowPlayingPresenting
    @ObservationIgnored private var resolveTask: Task<Void, Never>?
    @ObservationIgnored private var albumArtTask: Task<Void, Never>?

    /// How long playback may sit paused before the player and audio session
    /// are released (see ``schedulePausedRelease()``).
    @ObservationIgnored private let pausedReleaseTimeout: Duration
    @ObservationIgnored private var pausedReleaseTask: Task<Void, Never>?

    /// How long a stream may sit buffering before it is parked as paused
    /// (see ``scheduleStallCeiling(for:)``).
    @ObservationIgnored private let stallTimeout: Duration
    @ObservationIgnored private var stallCeilingTask: Task<Void, Never>?

    /// Whether `output.start` has run for the active station. False while the
    /// stream endpoint is still resolving, or after a pause during loading —
    /// in that case `resume()` must re-play rather than resume a nonexistent player.
    @ObservationIgnored private var outputStarted = false

    /// Set when the system interrupts playback that was active, so playback can
    /// resume automatically when the interruption ends with a resume hint.
    @ObservationIgnored private var resumeAfterInterruption = false

    /// Designated initializer with every collaborator explicit — what tests use.
    /// The iOS production defaults live in the convenience initializer below so
    /// this type (and its tests) build on platforms without AVAudioSession/UIKit.
    public init(
        directory: any RadioDirectoryProviding,
        output: any AudioOutput,
        nowPlayingCenter: any NowPlayingPresenting,
        pausedReleaseTimeout: Duration = .seconds(10 * 60),
        stallTimeout: Duration = .seconds(90)
    ) {
        self.directory = directory
        self.output = output
        self.nowPlayingCenter = nowPlayingCenter
        self.pausedReleaseTimeout = pausedReleaseTimeout
        self.stallTimeout = stallTimeout

        configureOutput()
        configureRemoteCommands()
    }

    #if canImport(UIKit)
    /// Production wiring: AVPlayer-backed audio and the system now-playing center.
    /// On iOS 27+ the now-playing surface is the NowPlaying framework's typed
    /// MediaSession; iOS 26 keeps the legacy MediaPlayer bridge. Both sit behind
    /// ``NowPlayingPresenting``, so nothing else changes with the OS version.
    public convenience init(directory: any RadioDirectoryProviding) {
        let nowPlayingCenter: any NowPlayingPresenting
        #if canImport(NowPlaying)
        if #available(iOS 27, *) {
            nowPlayingCenter = MediaSessionNowPlayingCenter()
        } else {
            nowPlayingCenter = NowPlayingCenter()
        }
        #else
        nowPlayingCenter = NowPlayingCenter()
        #endif

        self.init(
            directory: directory,
            output: AVPlayerAudioOutput(),
            nowPlayingCenter: nowPlayingCenter
        )
    }
    #endif

    // MARK: - Intents

    public func play(_ station: Station) {
        startPlayback(of: station)
        onStationPlayed?(station)
    }

    /// Starts (or restarts) the stream for `station` without treating it as a
    /// new listening choice: `onStationPlayed` (recents logging, play
    /// reporting) fires only from ``play(_:)``, so internal restarts — resume
    /// after the paused-release teardown, retry after a failure — don't
    /// double-log or double-report.
    private func startPlayback(of station: Station) {
        resolveTask?.cancel()
        albumArtTask?.cancel()
        albumArtTask = nil
        cancelPausedRelease()
        cancelStallCeiling()
        activeStation = station
        state = .loading(station)
        nowPlaying = nil
        albumArtURL = nil
        outputStarted = false
        resumeAfterInterruption = false

        resolveTask = Task { [weak self] in
            guard let self else { return }
            do {
                let endpoint = try await directory.streamEndpoint(for: station)
                guard Task.isCancelled == false, self.activeStation?.id == station.id else { return }
                self.output.start(url: endpoint.url)
                self.outputStarted = true
                self.nowPlayingCenter.update(station: station, track: nil, isPlaying: true, artworkURL: nil)
            } catch {
                guard Task.isCancelled == false, self.activeStation?.id == station.id else { return }
                self.state = .failed(error.localizedDescription)
                self.activeStation = nil
            }
        }
    }

    public func pause() {
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
                cancelPausedRelease()
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
        cancelPausedRelease()
        cancelStallCeiling()
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

    // MARK: - Wiring

    private func configureOutput() {
        output.onStatusChange = { [weak self] status in
            self?.handleStatusChange(status)
        }
        output.onTrackInfo = { [weak self] info in
            self?.handleTrackInfo(info)
        }
    }

    private var isOutputPlaying: Bool {
        if case .playing = state { return true }
        return false
    }

    private func handleStatusChange(_ status: AudioStatus) {
        guard let station = activeStation else { return }
        switch status {
        case .buffering:
            cancelPausedRelease()
            state = .buffering(station)
            scheduleStallCeiling(for: station)
        case .playing:
            cancelPausedRelease()
            cancelStallCeiling()
            state = .playing(station)
            nowPlayingCenter.update(station: station, track: nowPlaying, isPlaying: true, artworkURL: albumArtURL)
        case .paused:
            cancelStallCeiling()
            state = .paused(station)
            nowPlayingCenter.update(station: station, track: nowPlaying, isPlaying: false, artworkURL: albumArtURL)
            schedulePausedRelease()
        case let .failed(message):
            cancelPausedRelease()
            cancelStallCeiling()
            state = .failed(message)
        case .interruptionBegan:
            handleInterruptionBegan(station: station)
        case let .interruptionEnded(shouldResume):
            if resumeAfterInterruption, shouldResume {
                resume()
            }
            resumeAfterInterruption = false
        }
    }

    private func handleTrackInfo(_ info: AudioTrackInfo) {
        guard let station = activeStation else { return }

        // ICY pushes often repeat identical track info (the Live Activity
        // coordinator dedupes for the same reason). Ignore duplicates so the
        // lock screen doesn't flash back to station art and the album art
        // lookup isn't refired for a track already resolved.
        if let current = nowPlaying,
           current.stationID == station.id,
           current.title == info.title,
           current.artist == info.artist {
            return
        }

        let metadata = NowPlayingMetadata(
            stationID: station.id,
            title: info.title,
            artist: info.artist,
            receivedAt: Date()
        )
        nowPlaying = metadata
        // Clear any art from a previous track while resolution is in flight.
        albumArtURL = nil

        nowPlayingCenter.update(
            station: station,
            track: metadata,
            isPlaying: isOutputPlaying,
            artworkURL: albumArtURL
        )

        resolveAlbumArt(for: info)
    }

    /// Best-effort album art resolution: resolve asynchronously and re-push
    /// the now-playing surface with the resolved URL.
    private func resolveAlbumArt(for info: AudioTrackInfo) {
        guard let provider = albumArtURLProvider else { return }
        albumArtTask?.cancel()
        albumArtTask = Task { [weak self] in
            let resolvedURL = await provider(info)
            guard Task.isCancelled == false, let self else { return }
            // Only apply if the track hasn't changed while we awaited.
            guard self.nowPlaying?.title == info.title,
                  self.nowPlaying?.artist == info.artist else { return }
            self.albumArtURL = resolvedURL
            guard let station = self.activeStation, let resolvedURL else { return }
            self.nowPlayingCenter.update(
                station: station,
                track: self.nowPlaying,
                isPlaying: self.isOutputPlaying,
                artworkURL: resolvedURL
            )
        }
    }

    private func handleInterruptionBegan(station: Station) {
        switch state {
        case .playing, .buffering:
            // The system already paused the player; remember to resume.
            resumeAfterInterruption = true
            cancelStallCeiling()
            state = .paused(station)
            schedulePausedRelease()
        case .loading:
            // Don't let a pending start fire mid-interruption.
            resumeAfterInterruption = true
            resolveTask?.cancel()
            outputStarted = false
            state = .paused(station)
            schedulePausedRelease()
        default:
            break
        }
        nowPlayingCenter.update(station: station, track: nowPlaying, isPlaying: false, artworkURL: albumArtURL)
    }

    // MARK: - Resource hygiene

    /// Releases the player and audio session once playback has sat paused for
    /// `pausedReleaseTimeout`. Holding them longer keeps the `audio`
    /// background assertion (and the resident AVPlayerItem) alive for as long
    /// as the user stays paused — hours of background battery for no benefit,
    /// since live radio has no position to preserve: `resume()` restarts the
    /// stream to identical effect via its `outputStarted == false` path.
    ///
    /// `state`, `nowPlaying`, and the now-playing surface are deliberately
    /// left untouched — the lock screen keeps showing the paused station with
    /// a working play button, and observers see no state change.
    private func schedulePausedRelease() {
        pausedReleaseTask?.cancel()
        let timeout = pausedReleaseTimeout
        pausedReleaseTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self, Task.isCancelled == false else { return }
            guard case .paused = self.state else { return }
            self.output.stop()
            self.outputStarted = false
        }
    }

    private func cancelPausedRelease() {
        pausedReleaseTask?.cancel()
        pausedReleaseTask = nil
    }

    /// Bounds how long a stalled stream may sit buffering. AVPlayer's
    /// `automaticallyWaitsToMinimizeStalling` retries a stalled live stream
    /// indefinitely — with the app backgrounded (signal loss in a pocket)
    /// that keeps the network radio churning with no ceiling. After
    /// `stallTimeout` the stream is torn down and parked as `.paused` rather
    /// than `.failed`: a stall isn't a user error, and paused keeps the lock
    /// screen accurate with a play button that routes to the restart path.
    private func scheduleStallCeiling(for station: Station) {
        stallCeilingTask?.cancel()
        let timeout = stallTimeout
        stallCeilingTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self, Task.isCancelled == false else { return }
            guard case .buffering = self.state else { return }
            self.output.stop()
            self.outputStarted = false
            self.state = .paused(station)
            // Teardown invalidated the player's observation before pausing,
            // so no `.paused` status callback arrives — push the lock-screen
            // surface manually. No paused-release is scheduled: the player
            // and session are already gone.
            self.nowPlayingCenter.update(
                station: station,
                track: self.nowPlaying,
                isPlaying: false,
                artworkURL: self.albumArtURL
            )
        }
    }

    private func cancelStallCeiling() {
        stallCeilingTask?.cancel()
        stallCeilingTask = nil
    }

    private func configureRemoteCommands() {
        nowPlayingCenter.onPlay = { [weak self] in self?.resume() }
        nowPlayingCenter.onPause = { [weak self] in self?.pause() }
        nowPlayingCenter.onStop = { [weak self] in self?.stop() }
        nowPlayingCenter.onToggle = { [weak self] in self?.togglePlayPause() }
    }
}

#if canImport(UIKit)
public extension PlaybackController {
    /// A controller wired to preview data for SwiftUI previews.
    @MainActor
    static func preview() -> PlaybackController {
        PlaybackController(directory: PreviewRadioDirectory())
    }
}
#endif
