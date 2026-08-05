import Foundation
import RadioDirectory

// Internal wiring for `PlaybackController`: stream start/restart, audio-status
// handling, ICY track-info fan-out, and album-art resolution. Split out of
// PlaybackController.swift so the public state/intents surface stays a short,
// readable file; the timer-driven housekeeping and recovery it schedules lives
// one file further out, in PlaybackController+Recovery.swift. The controller's
// stored properties are `internal` (not `private`) to let these extensions drive
// them; none of that is public API.

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
        resumeWatchdogTimer.cancel()
        resumeAfterRouteChange = false
        activeStation = station
        state = .loading(station)
        outputStarted = false
        let streamGeneration = activeStreamGeneration &+ 1
        activeStreamGeneration = streamGeneration
        disarmInterruptionResume()
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
                // Reconnects reuse the endpoint resolved for the first attempt
                // rather than re-running resolution each backoff; a fresh
                // `play(_:)` clears the cache so it can't go stale across choices.
                let endpoint: StreamEndpoint
                if isReconnect, let cached = self.resolvedEndpoint {
                    endpoint = cached
                } else {
                    endpoint = try await directory.streamEndpoint(for: station)
                }
                guard Task.isCancelled == false, self.activeStation?.id == station.id else { return }
                self.resolvedEndpoint = endpoint
                self.tapToAudioTrace?.markResolved(url: endpoint.url)
                self.output.start(url: endpoint.url, streamGeneration: streamGeneration)
                self.outputStarted = true
                self.tapToAudioTrace?.markOutputStarted()
                // Pass the preserved track/art through: on a reconnect the
                // last-known track must stay on the lock screen while the
                // stream re-buffers (both are nil on a fresh start anyway).
                self.nowPlayingCenter.update(
                    station: station,
                    track: self.nowPlaying,
                    isPlaying: true,
                    artworkURL: self.albumArtURL
                )
            } catch let error as RadioDirectoryError {
                guard Task.isCancelled == false, self.activeStation?.id == station.id else { return }
                self.handleResolutionFailure(error, for: station)
            } catch {
                guard Task.isCancelled == false, self.activeStation?.id == station.id else { return }
                self.handleResolutionFailure(.transport(error.localizedDescription), for: station)
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
        tapToAudioTrace?.cancel()
        tapToAudioTrace = nil
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
            // Leaving `.paused` for `.buffering` is the output acknowledging a
            // resume (or a restart); the watchdog has nothing left to guard.
            resumeWatchdogTimer.cancel()
            state = .buffering(station)
            scheduleStallCeiling(for: station)
        case .playing:
            resumeAfterRouteChange = false
            pausedReleaseTimer.cancel()
            stallCeilingTimer.cancel()
            reconnectTimer.cancel()
            resumeWatchdogTimer.cancel()
            // A successful (re)connect clears the budget for the next drop.
            reconnectAttempts = 0
            state = .playing(station)
            tapToAudioTrace?.completeIfNeeded()
            tapToAudioTrace = nil
            nowPlayingCenter.update(station: station, track: nowPlaying, isPlaying: true, artworkURL: albumArtURL)
        case .paused:
            stallCeilingTimer.cancel()
            // A system-initiated pause (headphones unplugged, route change)
            // must win over a pending auto-reconnect just like a user pause.
            reconnectTimer.cancel()
            // Any pause before first `.playing` ends the trace: completing it
            // later would fold the pause duration into `firstPlayingMs`. (Once
            // `.playing` has happened the trace is already nil.)
            tapToAudioTrace?.cancel()
            tapToAudioTrace = nil
            state = .paused(station)
            nowPlayingCenter.update(station: station, track: nowPlaying, isPlaying: false, artworkURL: albumArtURL)
            schedulePausedRelease()
        case let .failed(playbackError):
            pausedReleaseTimer.cancel()
            stallCeilingTimer.cancel()
            resumeWatchdogTimer.cancel()
            tapToAudioTrace?.cancel()
            tapToAudioTrace = nil
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
        case let .interruptionEnded(shouldResume, otherAudioIsPlaying):
            handleInterruptionEnded(shouldResume: shouldResume, otherAudioIsPlaying: otherAudioIsPlaying)
        case .routeLost:
            handleRouteLost(station: station)
        case .routeAvailable:
            handleRouteAvailable()
        }
    }

    func handleTrackInfo(_ info: AudioTrackInfo) {
        guard let station = activeStation else { return }
        guard outputStarted else { return }
        guard info.streamGeneration == activeStreamGeneration else { return }

        // Engine metadata callbacks are delivered asynchronously, so an event
        // emitted for the *previous* station can land after a fast station
        // switch has already set `activeStation` to the new one. Legitimate
        // ICY metadata only flows once this station's stream has started;
        // any arriving track info for the old station is dropped by the
        // generation guard above, preventing stale attribution across surfaces.

        // Conservative gate: junk (a URL, the station's own name, promo copy,
        // a bare ID token) never reaches now-playing or history. A track that
        // fails the check is dropped, not blanked — the previous good track
        // (or nothing) stays on screen rather than flashing to empty.
        guard SongTitleFilter.isLikelySongTitle(info, stationName: station.name) else { return }

        // ICY pushes often repeat identical track info (the Live Activity
        // coordinator dedupes for the same reason). Ignore duplicates so the
        // lock screen doesn't flash back to station art and the album art
        // lookup isn't refired for a track already resolved.
        if let current = nowPlaying,
           current.stationID == station.id,
           current.title == info.title,
           current.artist == info.artist {
            // A repeated push is also the only signal on which a transiently
            // failed resource lookup can retry: AlbumArtLookup caches hits and
            // definitive misses but deliberately not transient failures, yet
            // nothing else re-invokes it for the same track — one network blip
            // would otherwise suppress album art on every surface for the
            // whole song. No-op while a resolution is in flight or once one
            // has produced a result; a cached miss answers without leaving
            // the process. (Re-firing onTrackHeard is safe: the history log
            // dedupes consecutive identical tracks.)
            if albumArtURL == nil, appleMusicURL == nil, albumArtTask == nil {
                resolveTrackResources(for: info)
            }
            return
        }

        // Clear any art/link from a previous track while resolution is in flight.
        // Order matters: observers (including the Live Activity coordinator)
        // must see the stale artwork clear before they see the new metadata, or
        // they can momentarily pair the new title with the previous track's art.
        albumArtURL = nil
        appleMusicURL = nil
        let metadata = NowPlayingMetadata(
            stationID: station.id,
            title: info.title,
            artist: info.artist,
            receivedAt: Date()
        )
        nowPlaying = metadata
        onTrackHeard?(HeardTrack(station: station, track: metadata, appleMusicURL: nil))

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
            // Resolution for the current track is complete; clearing the
            // handle is what re-arms this method's duplicate-push retry.
            // (A superseded task returns above and leaves
            // the handle owned by its replacement.)
            self.albumArtTask = nil
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

    func configureRemoteCommands() {
        nowPlayingCenter.onPlay = { [weak self] in self?.resume() }
        nowPlayingCenter.onPause = { [weak self] in self?.pause() }
        nowPlayingCenter.onStop = { [weak self] in self?.stop() }
        nowPlayingCenter.onToggle = { [weak self] in self?.togglePlayPause() }
    }
}
