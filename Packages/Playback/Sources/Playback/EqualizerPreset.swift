import Foundation

/// Audio equalizer presets, ported verbatim from the Android client's
/// `EqualizerPreset`/`EqualizerCurves` (`core/playback` in sir-android) so both
/// clients colour a station's sound identically.
///
/// Each preset owns its own gain ``curve`` — a pure function from normalized band
/// position (`0.0` = lowest frequency band, `1.0` = highest) to a normalized gain
/// fraction of the device/engine's supported range. Keeping the curve on the
/// preset (rather than a `switch` in the playback engine) makes every preset
/// independently testable without any platform audio dependency.
///
/// ``normal`` deliberately has no curve: it means "flat", i.e. 0 dB on every
/// band, which is **not** the same as the midpoint of an asymmetric gain range.
/// On hardware/engines whose range isn't centered on zero, the midpoint is not
/// flat, and "Normal" would quietly colour the sound.
public enum EqualizerPreset: Int, CaseIterable, Hashable, Sendable {
    case normal
    case bassBoost
    case vocal
    case treble

    /// Slope applied by the tilt-shaped presets (``bassBoost``, ``treble``).
    private static let tilt: Float = 0.6

    /// `nil` for ``normal`` (flat, 0 dB every band); otherwise a pure function
    /// from normalized band position to a normalized gain fraction, applied by
    /// ``EqualizerCurves``.
    public var curve: (@Sendable (Float) -> Float)? {
        switch self {
        case .normal:
            return nil
        case .bassBoost:
            return { position in (1 - position) * Self.tilt }
        case .vocal:
            return { position in
                switch position {
                case ..<0.3:
                    return 0.1 // cut bass
                case ..<0.7:
                    return 0.7 // boost mids
                default:
                    return 0.4 // slight boost highs
                }
            }
        case .treble:
            return { position in position * Self.tilt }
        }
    }

    /// User-facing name for this preset.
    public var displayName: String {
        switch self {
        case .normal:
            return String(localized: "Normal", bundle: .module)
        case .bassBoost:
            return String(localized: "Bass Boost", bundle: .module)
        case .vocal:
            return String(localized: "Vocal", bundle: .module)
        case .treble:
            return String(localized: "Treble", bundle: .module)
        }
    }
}
