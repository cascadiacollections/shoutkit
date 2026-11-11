import AudioLevels

// Live level meter wiring, split out of PlaybackController.swift for the same
// 400-line `file_length` reason as PlaybackController+SpatialAudio.swift.

public extension PlaybackController {
    /// Whether the active ``AudioOutput`` can meter what it plays. `false` for
    /// `AVPlayer`-backed engines and any ``AudioOutput`` that isn't also a
    /// ``RadioPlaybackEngine`` — meters hide rather than draw bars that never
    /// move.
    var supportsAudioLevels: Bool {
        (output as? any RadioPlaybackEngine)?.supportsAudioTaps ?? false
    }

    /// A live stream of per-band levels for what is playing.
    ///
    /// Each call attaches its own `AudioLevelMeter` plug-in to the engine, so
    /// Now Playing and the mini player can meter at once. The plug-in is detached
    /// when the stream ends, which is when the iterating task is cancelled. The
    /// stream finishes immediately when ``supportsAudioLevels`` is `false`.
    func audioLevels(bandCount: Int = AudioLevels.defaultBandCount) -> AsyncStream<AudioLevels> {
        guard let engine = output as? any RadioPlaybackEngine, engine.supportsAudioTaps,
              let meter = AudioLevelMeter(bandCount: bandCount)
        else {
            return AsyncStream { $0.finish() }
        }
        engine.addAudioTap(meter)
        // Captures the controller, not the engine: a main-actor class is
        // `Sendable`, an `any RadioPlaybackEngine` existential is not. `output`
        // is a `let`, so it is the same engine the meter was added to.
        meter.onTermination { [weak self, weak meter] in
            Task { @MainActor in
                guard let self, let meter else { return }
                (self.output as? any RadioPlaybackEngine)?.removeAudioTap(meter)
            }
        }
        return meter.levels
    }
}
