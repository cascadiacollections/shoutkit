/// One frame of a live level meter: a loudness value per frequency band, each
/// normalized to `0...1` (silence to full scale), lowest band first.
///
/// It describes what is playing *right now*, not a waveform over time. That
/// is the shape that fits live audio, which has no duration to lay out and no
/// position to scrub to.
public struct AudioLevels: Sendable, Equatable, Hashable {
    /// The band count the spec's golden vectors use, and the default everywhere.
    /// Few enough that each bar is wide enough to read on a phone, enough that
    /// the shape of the music still shows.
    public static let defaultBandCount = 24

    public let bands: [Float]

    public init(bands: [Float]) {
        self.bands = bands
    }

    /// Every band at zero — what a meter shows at rest.
    public static func silent(bandCount: Int = defaultBandCount) -> AudioLevels {
        AudioLevels(bands: Array(repeating: 0, count: bandCount))
    }

    /// These levels folded into `count` bands, each the loudest of the bands it
    /// covers. For a compact meter (a mini player's handful of bars) that wants
    /// the same motion as the full one rather than a second analysis.
    ///
    /// Returns `self` when `count` is not smaller than the current band count,
    /// and an empty frame for `count <= 0`.
    public func resampled(to count: Int) -> AudioLevels {
        guard count > 0 else { return AudioLevels(bands: []) }
        guard count < bands.count else { return self }
        return AudioLevels(bands: (0 ..< count).map { group in
            let lower = group * bands.count / count
            let upper = max(lower + 1, (group + 1) * bands.count / count)
            return bands[lower ..< upper].max() ?? 0
        })
    }
}
