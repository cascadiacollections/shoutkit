#if canImport(UIKit) && !os(watchOS)
import AudioStreaming
import AVFoundation
import Foundation

// The equalizer attach point on AudioStreaming's `AVAudioEngine`-backed node
// graph. AudioStreaming's `AudioPlayer.attach(node:)` inserts a custom
// `AVAudioNode` between its rate node and main mixer (see the "Adding custom
// audio nodes to AudioPlayer" section of its README), which is what makes an
// equalizer possible here at all — `AVPlayer` (the previous engine, and the
// one `WatchRadioPlaybackEngine` still uses) has no supported way to insert a
// filter into its render chain. Split out of AudioStreamingPlaybackEngine.swift
// for the same `file_length` reason as the `+Session` split.
extension AudioStreamingPlaybackEngine {
    /// Number of equalizer bands. Matches the Android client's default so both
    /// clients apply the same curve shape.
    static let equalizerBandCount = 5

    /// Center frequencies (Hz) for the bands, roughly log-spaced across the
    /// audible range.
    static let equalizerBandFrequencies: [Float] = [60, 230, 910, 3600, 14_000]

    /// Gain range, in dB, applied at each band. Deliberately narrower than
    /// `AVAudioUnitEQ`'s full `-96...24` range: it's a listening-color preset,
    /// not a mastering tool, and a conservative range avoids clipping/gain
    /// staging surprises on top of a live stream already at unity gain.
    static let equalizerMinGain: Float = -12
    static let equalizerMaxGain: Float = 12

    public var supportsEqualizer: Bool { true }

    public func setEqualizerPreset(_ preset: EqualizerPreset) {
        currentEqualizerPreset = preset
        let equalizer = equalizerNode ?? attachEqualizer()
        applyGains(for: preset, to: equalizer)
    }

    /// Creates, attaches, and remembers the equalizer node. Called lazily from
    /// ``setEqualizerPreset(_:)`` and again from `handleMediaServicesReset()`
    /// (via `reattachEqualizerIfNeeded()`), since a reset tears down the whole
    /// `AVAudioEngine` this node lives in along with everything else.
    @discardableResult
    func attachEqualizer() -> AVAudioUnitEQ {
        let equalizer = AVAudioUnitEQ(numberOfBands: Self.equalizerBandCount)
        for (index, band) in equalizer.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = Self.equalizerBandFrequencies[index]
            band.bandwidth = 1.0
            band.bypass = false
        }
        player.attach(node: equalizer)
        equalizerNode = equalizer
        return equalizer
    }

    /// Re-attaches the equalizer to the rebuilt player/engine after a
    /// media-services reset, if a preset had been applied before the reset.
    /// Without this the equalizer would silently vanish on the next reset —
    /// the new `AVAudioEngine` has no memory of the old node.
    func reattachEqualizerIfNeeded() {
        equalizerNode = nil
        guard currentEqualizerPreset != .normal else { return }
        let equalizer = attachEqualizer()
        applyGains(for: currentEqualizerPreset, to: equalizer)
    }

    private func applyGains(for preset: EqualizerPreset, to equalizer: AVAudioUnitEQ) {
        let gains = EqualizerCurves.levels(
            for: preset,
            bandCount: Self.equalizerBandCount,
            minGain: Self.equalizerMinGain,
            maxGain: Self.equalizerMaxGain
        )
        for (index, gain) in gains.enumerated() where equalizer.bands.indices.contains(index) {
            equalizer.bands[index].gain = gain
        }
    }
}

#endif
