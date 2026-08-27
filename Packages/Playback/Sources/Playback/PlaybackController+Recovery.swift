import Foundation
import RadioDirectory

// `PlaybackController`'s timer-driven housekeeping and recovery: the paused
// release and stall ceiling (battery hygiene), the resume watchdog, and the
// bounded auto-reconnect. Split out of PlaybackController+Internals.swift for
// the same reason that file was split out of PlaybackController.swift — the
// 400-line `file_length` limit, which CI enforces via `swiftlint --strict`.
// Every window here is injectable so tests use milliseconds instead of minutes;
// none of them is a user-facing setting.

extension PlaybackController {
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

    /// Guards a resume the output silently drops on the floor.
    ///
    /// `output.resume()` is best-effort: a streaming engine can refuse to resume
    /// a player whose stream is no longer alive, and refuse *quietly* — no audio
    /// and no status callback. AudioStreaming's `resume()` returns immediately
    /// unless its own state is exactly `paused` (which it isn't after the server
    /// closes a live stream, or after the system stops the engine for an
    /// interruption), and `AVPlayer.play()` does nothing for a failed or ended
    /// item. The controller would then sit in `.paused` indefinitely, with every
    /// further toggle resuming the same dead player — the reported symptom that
    /// only choosing another station cleared.
    ///
    /// So: if `state` hasn't left `.paused` shortly after a resume, tear the
    /// player down and rejoin the stream. That's the station-switch workaround,
    /// automated, and it stays correct for any ``AudioOutput`` rather than
    /// encoding one engine's quirk.
    func scheduleResumeWatchdog(for station: Station) {
        resumeWatchdogTimer.schedule(after: resumeWatchdogTimeout) { [weak self] in
            guard let self,
                  case .paused = self.state,
                  self.activeStation?.id == station.id else { return }
            self.output.stop()
            self.outputStarted = false
            // The listener just asked for audio: give the rejoin a full budget
            // rather than whatever an earlier drop left behind.
            self.reconnectAttempts = 0
            // `isReconnect` reuses the resolved endpoint and keeps the
            // last-known track on screen while the stream re-buffers. This is a
            // rejoin, not a new listening choice, so `onStationPlayed` stays
            // silent — same contract as the paused-release restart.
            self.startPlayback(of: station, isReconnect: true)
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

    /// A stream that played through to the end of its content: the station was
    /// a finite programme, not an endless one.
    ///
    /// The default is to stop there — park as `.paused` so the mini-player and
    /// the lock screen stay put with a play button that replays the programme
    /// (`resume()` takes the `outputStarted == false` path and starts the stream
    /// again). This is the one behaviour a finished broadcast must *not* have:
    /// reaching this through `.failed` instead sent it into
    /// ``attemptReconnect(for:fallback:)``, which rejoined the stream from the
    /// top — a newscast that played itself four times over before giving up.
    ///
    /// With looping opted in, the restart is exactly that reconnect path minus
    /// the failure: an internal restart, so `onStationPlayed` stays silent (this
    /// is not a new listening choice) and the resolved endpoint is reused.
    func handleEndOfStream(for station: Station) {
        pausedReleaseTimer.cancel()
        stallCeilingTimer.cancel()
        reconnectTimer.cancel()
        resumeWatchdogTimer.cancel()
        tapToAudioTrace?.cancel()
        tapToAudioTrace = nil
        // The content is spent either way, so the engine holds nothing worth
        // resuming; tear it down so `resume()` restarts rather than resuming a
        // player parked at the end of its stream.
        output.stop()
        outputStarted = false
        // Ending cleanly is a success, not a drop: the next real failure gets a
        // full budget rather than whatever this play-through left behind.
        reconnectAttempts = 0

        guard isStreamLoopingEnabledProvider() else {
            state = .paused(station)
            pushNowPlaying(for: station, isPlaying: false)
            // No paused-release to schedule — the player and audio session are
            // already gone, which is what that timer exists to accomplish.
            return
        }

        startPlayback(of: station, isReconnect: true)
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
            pushNowPlaying(for: station, isPlaying: false)
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
}
