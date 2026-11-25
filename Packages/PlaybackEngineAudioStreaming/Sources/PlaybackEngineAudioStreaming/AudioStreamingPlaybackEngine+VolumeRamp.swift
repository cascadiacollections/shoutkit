import Foundation

// Fades `player.volume` in from silence on a rejoin, split out of
// AudioStreamingPlaybackEngine.swift for the same reason the session and
// equalizer extensions were — the 400-line `file_length` limit.
//
// Live radio has no position to resume: every reconnect — after an
// interruption, a stall, or a dropped connection — rejoins the stream fresh,
// at whatever the live edge currently is. Doing that at full volume reads as
// a click or a jump-cut; a short fade masks the discontinuity without being
// perceptible itself.
//
// The fade is armed only by `silenceForUpcomingPlayback()`. AudioStreaming
// also reports `.playing` when a buffer underrun recovers, and the player is
// already at full volume then. Ramping that transition drops the stream to
// near silence and swells it back.

extension AudioStreamingPlaybackEngine {
    /// How long a rejoin takes to fade from silent to full volume, and how many
    /// steps it takes to get there. Short enough that a listener never notices
    /// the ramp — only its absence of a pop.
    static let volumeRampDuration = Duration.milliseconds(350)
    static let volumeRampSteps = 14

    /// Zeroes the player's volume ahead of a rejoin, so whatever
    /// ``fadeInVolume()`` finds when `.playing` next arrives starts from
    /// silence rather than whatever level a previous ramp left it at.
    func silenceForUpcomingPlayback() {
        volumeRampTask?.cancel()
        volumeRampTask = nil
        volumeRampArm.arm()
        player.volume = 0
    }

    /// Ramps the player from silent to full volume over ``volumeRampDuration``,
    /// and only when ``silenceForUpcomingPlayback()`` armed it. A `.playing`
    /// that was not armed leaves the current volume, and leaves a fade that
    /// is already running alone: cancelling it here would freeze the mixer
    /// part way up.
    func fadeInVolume() {
        guard volumeRampArm.consume() else { return }
        volumeRampTask?.cancel()
        volumeRampTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let steps = Self.volumeRampSteps
            let stepDuration = Self.volumeRampDuration / steps
            for step in 1 ... steps {
                try? await Task.sleep(for: stepDuration)
                guard Task.isCancelled == false else { return }
                self.player.volume = Float(step) / Float(steps)
            }
        }
    }
}

/// Whether the next `.playing` transition is a rejoin that was silenced first.
struct VolumeRampArm: Equatable {
    private(set) var isArmed = false

    mutating func arm() {
        isArmed = true
    }

    /// `true` once, for the `.playing` that follows ``arm()``. Every later
    /// call is `false` until the next arm, so a buffer recovery does not
    /// start another fade.
    mutating func consume() -> Bool {
        defer { isArmed = false }
        return isArmed
    }
}
