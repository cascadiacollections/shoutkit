/// Display auto-gain for a level meter: scales each frame so its loudest band
/// sits near full height, against a reference that jumps up to any louder
/// frame and decays slowly, never below ``minimumReference``.
///
/// Streams differ by 10 dB or more in mastering, so a fixed scale that suits a
/// loud station draws a quiet one as a row of dots — which is what KEXP looked
/// like on the iOS simulator before this. The floor keeps quiet passages and
/// silence from being blown up to full scale. Display only: the analysis and
/// its golden vectors are unaffected (docs/audio-levels-spec.md, "Drawing").
public struct AutoGain: Sendable, Equatable {
    /// The quietest loudest-band level that is scaled to full height.
    public static let minimumReference: Float = 0.3

    /// How fast the reference falls back toward quieter material, in full
    /// scale per second.
    public static let decayRate: Float = 0.15

    public private(set) var reference: Float = minimumReference
    private var lastUpdate: ContinuousClock.Instant?

    public init() {}

    /// Advances the reference to `now` and returns `levels` scaled by it,
    /// clamped to `0...1`.
    public mutating func apply(to levels: AudioLevels, at now: ContinuousClock.Instant = .now) -> AudioLevels {
        let elapsed = lastUpdate.map { Self.seconds(now - $0) } ?? 0
        lastUpdate = now
        let loudest = levels.bands.max() ?? 0
        reference = max(Self.minimumReference, loudest, reference - Self.decayRate * elapsed)
        return AudioLevels(bands: levels.bands.map { min(1, $0 / reference) })
    }

    private static func seconds(_ duration: Duration) -> Float {
        let (seconds, attoseconds) = duration.components
        return Float(seconds) + Float(attoseconds) / 1e18
    }
}
