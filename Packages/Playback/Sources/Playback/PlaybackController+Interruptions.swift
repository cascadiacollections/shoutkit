import Foundation
import RadioDirectory

// How `PlaybackController` responds to the OS taking the audio session away and
// giving it back: a phone call, an alarm, Siri, another app claiming playback.
// The two halves are deliberately asymmetric — an interruption *beginning* is
// unambiguous (the audio is already silent, so mirror that faithfully), while an
// interruption *ending* is a policy decision about whether the listener wants
// their station back. That policy is the whole reason this file exists rather
// than a branch in `handleStatusChange`.

extension PlaybackController {
    func handleRouteLost() {
        switch state {
        case .playing, .buffering:
            resumeAfterRouteChange = true
            output.pause()
        default:
            break
        }
    }

    func handleRouteAvailable() {
        guard resumeAfterRouteChange else { return }
        resume()
    }

    func handleInterruptionBegan(station: Station) {
        // A reconnect must not fire mid-interruption: it would try to grab the
        // audio session during the call and clobber the arming below in
        // `startPlayback`, killing the auto-resume when the call ends.
        reconnectTimer.cancel()
        // Nor a resume watchdog — the interruption owns the paused state now.
        resumeWatchdogTimer.cancel()
        // Arming is strictly per-interruption, so this clears any arm left over
        // from an earlier one. iOS does not guarantee an `.ended` for every
        // `.began` (a route that disconnects, or the app being suspended through
        // the interruption, can end it silently), and a stale arm meant the
        // *next* interruption to end with a resume hint started audio the
        // listener had never asked for — from a station they had left paused.
        disarmInterruptionResume()
        // Whether the output is left holding a player that should be told about
        // the pause (the `.loading` branch tears its player down instead).
        var shouldPauseOutput = false
        switch state {
        case .playing, .buffering:
            // The system already paused the player; remember to resume.
            armInterruptionResume()
            stallCeilingTimer.cancel()
            state = .paused(station)
            schedulePausedRelease()
            shouldPauseOutput = outputStarted
        case .loading:
            // Don't let a pending start fire mid-interruption.
            armInterruptionResume()
            resolveTask?.cancel()
            tapToAudioTrace?.cancel()
            tapToAudioTrace = nil
            // The stream may already have started even though no status has
            // landed yet (`state` only leaves `.loading` on the first status
            // callback). Tear it down rather than leaving it streaming through
            // the interruption; `resume()` restarts from `outputStarted == false`.
            if outputStarted {
                output.stop()
            }
            outputStarted = false
            state = .paused(station)
            schedulePausedRelease()
        default:
            break
        }
        nowPlayingCenter.update(station: station, track: nowPlaying, isPlaying: false, artwork: .resolved(albumArtURL))

        // Tell the output it is paused too, not just our own state machine. The
        // system silences the audio without informing the streaming engine, and
        // an engine that never learned it was paused can refuse to resume later
        // (AudioStreaming's `resume()` acts only on its own `.paused` state),
        // which used to leave playback stuck until the listener switched
        // stations. Done last so the status callback it may emit synchronously
        // lands after this transition instead of racing it.
        if shouldPauseOutput {
            output.pause()
        }
    }

    /// Decides whether the end of an interruption resumes the station.
    ///
    /// The system's `shouldResume` hint is honored whenever it is set. When it is
    /// *absent*, though, "stay paused" is only right some of the time: iOS omits
    /// the hint for plenty of interruptions that plainly should resume, and the
    /// listener's radio then stays silent — in a pocket, in a car — until they
    /// notice and press play. For a live-radio app that is the loudest possible
    /// failure, so a hintless end still resumes, but only when all three of the
    /// conditions that separate "the OS borrowed the session for a moment" from
    /// "the listener moved on to something else" hold:
    ///
    /// - the stream was running when the interruption began (the arm), so nothing
    ///   auto-plays that the listener had already paused;
    /// - no other app holds audio now, so we never yank the session back from
    ///   whatever they started meanwhile; and
    /// - the interruption ended inside ``hintlessResumeWindow``, because a long
    ///   one is a listener who moved on, not an alert.
    ///
    /// Deliberately not a user-facing setting: every branch here is either
    /// "restore what was playing" or "leave the listener's choice alone", and
    /// neither is a preference anyone should have to find.
    func handleInterruptionEnded(shouldResume: Bool, otherAudioIsPlaying: Bool) {
        let wasArmed = resumeAfterInterruption
        let isInsideHintlessWindow = mayResumeWithoutSystemHint
        disarmInterruptionResume()

        guard wasArmed else { return }
        let mayResume = shouldResume || (isInsideHintlessWindow && otherAudioIsPlaying == false)
        guard mayResume else { return }
        resume()
    }

    /// Remembers that this interruption silenced audio that *was* running, and
    /// opens the window inside which a hintless end may still resume it.
    private func armInterruptionResume() {
        resumeAfterInterruption = true
        mayResumeWithoutSystemHint = true
        hintlessResumeWindowTimer.schedule(after: hintlessResumeWindow) { [weak self] in
            // The interruption is still going and has outlived the window: from
            // here on only the system's own hint may resume it.
            self?.mayResumeWithoutSystemHint = false
        }
    }

    /// Forgets any pending interruption auto-resume. Called wherever a newer
    /// intention supersedes it: a user pause or stop, a fresh start, and the
    /// beginning of the next interruption.
    func disarmInterruptionResume() {
        resumeAfterInterruption = false
        mayResumeWithoutSystemHint = false
        hintlessResumeWindowTimer.cancel()
    }
}
