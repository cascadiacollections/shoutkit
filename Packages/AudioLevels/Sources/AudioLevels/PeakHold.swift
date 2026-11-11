/// Peak caps for a level meter: each band's cap jumps to any louder level,
/// holds there for ``holdDuration``, then falls at ``fallRate`` until a level
/// catches it. Time-based rather than frame-based, so caps behave the same
/// whether frames arrive ten or thirty times a second.
public struct PeakHold: Sendable, Equatable {
    public static let holdDuration = Duration.milliseconds(600)

    /// Full scale per second.
    public static let fallRate: Float = 0.9

    public private(set) var peaks: [Float]
    private var heldSince: [ContinuousClock.Instant?]
    private var lastUpdate: ContinuousClock.Instant?

    public init(bandCount: Int = AudioLevels.defaultBandCount) {
        peaks = Array(repeating: 0, count: bandCount)
        heldSince = Array(repeating: nil, count: bandCount)
    }

    /// Advances the caps to `now` against `levels`. A change in band count
    /// resets them.
    public mutating func update(with levels: AudioLevels, at now: ContinuousClock.Instant = .now) {
        if levels.bands.count != peaks.count {
            self = PeakHold(bandCount: levels.bands.count)
        }
        let elapsed = lastUpdate.map { Self.seconds(now - $0) } ?? 0
        lastUpdate = now
        for (band, level) in levels.bands.enumerated() {
            if level >= peaks[band] {
                peaks[band] = level
                heldSince[band] = now
                continue
            }
            if let since = heldSince[band], now - since < Self.holdDuration {
                continue
            }
            heldSince[band] = nil
            peaks[band] = max(level, peaks[band] - Self.fallRate * elapsed)
        }
    }

    private static func seconds(_ duration: Duration) -> Float {
        let (seconds, attoseconds) = duration.components
        return Float(seconds) + Float(attoseconds) / 1e18
    }
}
