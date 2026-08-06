import Foundation

/// Pure band-level math for the equalizer, ported verbatim from the Android
/// client's `EqualizerCurves` (`core/playback` in sir-android).
///
/// Isolated from any platform audio type (`AVAudioUnitEQ` on iOS,
/// `android.media.audiofx.Equalizer` on Android) so the curve behaviour can be
/// verified with plain unit tests; the playback engine only has to read the
/// device/engine's band count and gain range and push the resulting values.
public enum EqualizerCurves {
    /// Maps `preset` onto `bandCount` bands within the supported gain range, in dB.
    ///
    /// - Parameters:
    ///   - minGain: lowest supported band gain, in dB.
    ///   - maxGain: highest supported band gain, in dB.
    public static func levels(
        for preset: EqualizerPreset,
        bandCount: Int,
        minGain: Float,
        maxGain: Float
    ) -> [Float] {
        guard let curve = preset.curve else {
            return Array(repeating: 0, count: max(bandCount, 0))
        }
        return levels(
            bandCount: bandCount,
            minGain: minGain,
            maxGain: maxGain,
            range: maxGain - minGain,
            curve: curve
        )
    }

    /// Distributes `curve` across `bandCount` bands.
    ///
    /// Band `i` sits at normalized position `i / (bandCount - 1)`; the curve's
    /// output is treated as a fraction of `range` above `minGain` and clamped
    /// into the supported `[minGain, maxGain]` window.
    static func levels(
        bandCount: Int,
        minGain: Float,
        maxGain: Float,
        range: Float,
        curve: (Float) -> Float
    ) -> [Float] {
        guard bandCount > 0 else { return [] }
        let denominator = Float(max(bandCount - 1, 1))
        return (0..<bandCount).map { band in
            let position = Float(band) / denominator
            let value = minGain + range * curve(position)
            return min(max(value, minGain), maxGain)
        }
    }
}
