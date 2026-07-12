import Foundation
import RadioDirectory

// Internal wiring for `PlaybackController`: stream start/restart, audio-status
// handling, ICY track-info fan-out, album-art resolution, and the resource-
// hygiene timers (paused release, stall ceiling, bounded auto-reconnect). Split
// out of PlaybackController.swift so the public state/intents surface stays a
// short, readable file. The controller's stored properties are `internal` (not
// `private`) to let this extension drive them; none of that is public API.

// MARK: - Wiring

extension PlaybackController {
    /// Starts (or restarts) the stream for `station` without treating it as a
    /// new listening choice: `onStationPlayed` (recents logging, play
    /// reporting) fires only from ``play(_:)``, so internal restarts — resume
    /// after the paused-release teardown, retry after a failure — don't
    /// double-log or double-report.
    func startPlayback(of station: Station, isReconnect: Bool = false) {
        resolveTask?.cancel()
        albumArtTask?.cancel()
        albumArtTask = nil
        pausedReleaseTimer.cancel()
        stallCeilingTimer.cancel()
        reconnectTimer.cancel()
        activeStation = station
        state = .loading(station)
        outputStarted = false
        resumeAfterInterruption = false
        // A reconnect keeps the last-known track on screen while it re-buffers
        // (ICY repopulates it on success) and must NOT reset the attempt
        // counter — resetting here would refill the budget every retry and
        // loop forever. A fresh start clears both.
        if !isReconnect {
            nowPlaying = nil
            albumArtURL = nil
            appleMusicURL = nil
        }

        resolveTask = Task { [weak self] in
            guard let self else { return }
            do {
                let endpoint = try await directory.streamEndpoint(for: station)
                guard Task.isCancelled == false, self.activeStation?.id == station.id else { return }
                self.output.start(url: endpoint.url)
                self.outputStarted = true
                // Pass the preserved track/art through: on a reconnect the
                // last-known track must stay on the lock screen while the
                // stream re-buffers (both are nil on a fresh start anyway).
                self.nowPlayingCenter.update(
                    station: station,
                    track: self.nowPlaying,
                    isPlaying: true,
                    artworkURL: self.albumArtURL
                )
            } catch let error {
                guard Task.isCancelled == false, self.activeStation?.id == station.id else { return }
                self.handleResolutionFailure(error, for: station)
            }
        }
    }

    /// Endpoint resolution fails for the same transient reasons the stream
    /// itself does (tunnel, cell handoff), so retryable failures get the same
    /// bounded reconnect budget instead of surfacing `.failed` at once — which
    /// matters most when the failure happens *during* a scheduled reconnect,
    /// where bailing out would abandon the rest of the budget. `activeStation`
    /// is kept either way so the failed state stays recoverable via
    /// `resume()`/`togglePlayPause()`.
    func handleResolutionFailure(_ error: RadioDirectoryError, for station: Station) {
        let playbackError = PlaybackError.directory(error)
        let fallback = PlaybackState.failed(playbackError)
        if playbackError.isRetryable == false {
            state = fallback
            nowPlayingCenter.update(station: station, track: nowPlaying, isPlaying: false, artworkURL: albumArtURL)
        } else {
            attemptReconnect(for: station, fallback: fallback)
        }
    }

    func configureOutput() {
        output.onStatusChange = { [weak self] status in
            self?.handleStatusChange(status)
        }
        output.onTrackInfo = { [weak self] info in
            self?.handleTrackInfo(info)
        }
    }

    var isOutputPlaying: Bool {
        if case .playing = state { return true }
        return false
    }

    func handleStatusChange(_ status: AudioStatus) {
        guard let station = activeStation else { return }
        switch status {
        case .buffering:
            pausedReleaseTimer.cancel()
            state = .buffering(station)
            scheduleStallCeiling(for: station)
        case .playing:
            pausedReleaseTimer.cancel()
            stallCeilingTimer.cancel()
            reconnectTimer.cancel()
            // A successful (re)connect clears the budget for the next drop.
            reconnectAttempts = 0
            state = .playing(station)
            nowPlayingCenter.update(station: station, track: nowPlaying, isPlaying: true, artworkURL: albumArtURL)
        case .paused:
            stallCeilingTimer.cancel()
            // A system-initiated pause (headphones unplugged, route change)
            // must win over a pending auto-reconnect just like a user pause.
            reconnectTimer.cancel()
            state = .paused(station)
            nowPlayingCenter.update(station: station, track: nowPlaying, isPlaying: false, artworkURL: albumArtURL)
            schedulePausedRelease()
        case let .failed(playbackError):
            pausedReleaseTimer.cancel()
            stallCeilingTimer.cancel()
            // Tear the dead player down before retrying: a failed AVPlayerItem
            // is unrecoverable, so `resume()` must never find `outputStarted`
            // still true and try to resume it — and on the give-up path the
            // player and audio session must not stay resident behind a
            // terminal `.failed`.
            output.stop()
            outputStarted = false
            // A mid-play failure is usually transient; retry before giving up.
            attemptReconnect(for: station, fallback: .failed(playbackError))
        case .interruptionBegan:
            handleInterruptionBegan(station: station)
        case let .interruptionEnded(shouldResume):
            if resumeAfterInterruption, shouldResume {
                resume()
            }
            resumeAfterInterruption = false
        }
    }

    func handleTrackInfo(_ info: AudioTrackInfo) {
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
        onTrackHeard?(HeardTrack(station: station, track: metadata, appleMusicURL: nil))
        // Clear any art/link from a previous track while resolution is in flight.
        albumArtURL = nil
        appleMusicURL = nil

        nowPlayingCenter.update(
            station: station,
            track: metadata,
            isPlaying: isOutputPlaying,
            artworkURL: albumArtURL
        )

        resolveTrackResources(for: info)
    }

    /// Best-effort resource resolution: resolve album art and the Apple Music
    /// link asynchronously, publish both, and re-push the now-playing surface
    /// with the resolved artwork (the lock screen has no link affordance).
    func resolveTrackResources(for info: AudioTrackInfo) {
        guard let provider = trackResourcesProvider else { return }
        albumArtTask?.cancel()
        albumArtTask = Task { [weak self] in
            let resources = await provider(info)
            guard Task.isCancelled == false, let self else { return }
            // Only apply if the track hasn't changed while we awaited.
            guard self.nowPlaying?.title == info.title,
                  self.nowPlaying?.artist == info.artist else { return }
            self.albumArtURL = resources.artworkURL
            self.appleMusicURL = resources.appleMusicURL
            if let station = self.activeStation, let metadata = self.nowPlaying {
                self.onTrackHeard?(
                    HeardTrack(station: station, track: metadata, appleMusicURL: resources.appleMusicURL)
                )
            }
            guard let station = self.activeStation, let artworkURL = resources.artworkURL else { return }
            self.nowPlayingCenter.update(
                station: station,
                track: self.nowPlaying,
                isPlaying: self.isOutputPlaying,
                artworkURL: artworkURL
            )
        }
    }

    func handleInterruptionBegan(station: Station) {
        // A reconnect must not fire mid-interruption: it would try to grab the
        // audio session during the call and clobber `resumeAfterInterruption`
        // in `startPlayback`, killing the auto-resume when the call ends.
        reconnectTimer.cancel()
        switch state {
        case .playing, .buffering:
            // The system already paused the player; remember to resume.
            resumeAfterInterruption = true
            stallCeilingTimer.cancel()
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
    /// `pausedReleaseTimeout` — otherwise a paused app keeps the `audio`
    /// background assertion (and the resident AVPlayerItem) alive for hours.
    /// Live radio has no position to lose: `resume()` restarts the stream via
    /// its `outputStarted == false` path. `state`, `nowPlaying`, and the
    /// lock-screen surface stay untouched, so the release is invisible and
    /// the lock-screen play button keeps working.
    func schedulePausedRelease() {
        pausedReleaseTimer.schedule(after: pausedReleaseTimeout) { [weak self] in
            guard let self, case .paused = self.state else { return }
            self.output.stop()
            self.outputStarted = false
        }
    }

    /// Bounds how long a stalled stream may sit buffering — AVPlayer's
    /// `automaticallyWaitsToMinimizeStalling` otherwise retries a stalled
    /// live stream forever, churning the network radio in the background.
    /// The stream is parked as `.paused` rather than `.failed`: a stall isn't
    /// a user error, and paused keeps the lock screen accurate with a play
    /// button that routes to the restart path.
    func scheduleStallCeiling(for station: Station) {
        stallCeilingTimer.schedule(after: stallTimeout) { [weak self] in
            guard let self, case .buffering = self.state else { return }
            self.output.stop()
            self.outputStarted = false
            // Try to recover the stalled stream before parking it. When the
            // reconnect budget is spent, `attemptReconnect` parks as `.paused`
            // and pushes the lock-screen surface (teardown above suppressed the
            // player's own `.paused` callback). No paused-release is scheduled
            // on the give-up path: the player and session are already gone.
            self.attemptReconnect(for: station, fallback: .paused(station))
        }
    }

    /// Bounded, backed-off automatic reconnect. A "reconnect" for live radio is
    /// just a fresh ``startPlayback(of:isReconnect:)`` (there's no position to
    /// resume), preserving the last-known track so the lock screen stays put
    /// while it re-buffers. Once the attempt budget is spent, `fallback` — the
    /// terminal state we'd have shown with no reconnect at all — is applied and
    /// the lock-screen surface is refreshed to match.
    func attemptReconnect(for station: Station, fallback: PlaybackState) {
        guard reconnectAttempts < maxReconnectAttempts else {
            reconnectAttempts = 0
            state = fallback
            nowPlayingCenter.update(
                station: station,
                track: nowPlaying,
                isPlaying: false,
                artworkURL: albumArtURL
            )
            return
        }

        reconnectAttempts += 1
        // Exponential backoff: base × 1, 2, 4, … so a flapping network isn't
        // hammered and the budget spans a useful window.
        let delay = reconnectBaseDelay * (1 << (reconnectAttempts - 1))
        // Keep `.buffering` so rows show a spinner and the lock screen stays
        // sane; ICY will refresh the track once the stream is back.
        state = .buffering(station)
        reconnectTimer.schedule(after: delay) { [weak self] in
            guard let self, self.activeStation?.id == station.id else { return }
            self.startPlayback(of: station, isReconnect: true)
        }
    }

    func configureRemoteCommands() {
        nowPlayingCenter.onPlay = { [weak self] in self?.resume() }
        nowPlayingCenter.onPause = { [weak self] in self?.pause() }
        nowPlayingCenter.onStop = { [weak self] in self?.stop() }
        nowPlayingCenter.onToggle = { [weak self] in self?.togglePlayPause() }
    }
}
