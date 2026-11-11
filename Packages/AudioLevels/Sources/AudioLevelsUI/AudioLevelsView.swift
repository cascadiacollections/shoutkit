import AudioLevels
import SwiftUI

/// Bars for an ``AudioLevels`` frame, drawn in the current foreground style.
///
/// Data-driven: give it the newest frame and it animates toward it. Where the
/// frames come from — an ``AudioLevelMeter`` on your engine's tap, a test, a
/// preview — is the caller's business.
///
/// ```swift
/// AudioLevelsView(levels: frame, style: .mirrored)
///     .frame(height: 28)
///     .foregroundStyle(.tint)
/// ```
///
/// Decorative by default (hidden from accessibility), because a meter repeats
/// what a "playing" indicator already says. With Reduce Motion on it still
/// draws, but jumps between frames instead of animating.
public struct AudioLevelsView: View {
    public enum Style: Sendable, Hashable {
        /// Bars grow up from a baseline.
        case bars
        /// Bars grow out from a center line, both ways — a broadcast meter.
        case mirrored
    }

    /// Tap engines on Apple platforms deliver about ten frames a second; easing
    /// each change over slightly longer than that interval turns steps into
    /// motion.
    public static let defaultAnimation = Animation.easeOut(duration: 0.12)

    /// Bars are drawn at `level ^ displayExponent` of the available height. Real
    /// stations land mostly between 0.1 and 0.4 per band, which drawn linearly
    /// is a few points of bar — a dotted line, not a meter. 0.6 lifts that range
    /// to roughly a quarter to a half of full height and leaves silence at zero
    /// and full scale at full. Display only: the analysis and its golden
    /// vectors are unaffected (docs/audio-levels-spec.md, "Drawing").
    public static let defaultDisplayExponent: Float = 0.6

    private let levels: AudioLevels
    private let style: Style
    private let showsPeaks: Bool
    private let barSpacing: CGFloat
    private let minimumBarHeight: CGFloat
    private let animation: Animation?
    private let displayExponent: Float

    @State private var peakHold = PeakHold()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        levels: AudioLevels,
        style: Style = .mirrored,
        showsPeaks: Bool = true,
        barSpacing: CGFloat = 3,
        minimumBarHeight: CGFloat = 3,
        animation: Animation? = defaultAnimation,
        displayExponent: Float = defaultDisplayExponent,
    ) {
        self.levels = levels
        self.style = style
        self.showsPeaks = showsPeaks
        self.barSpacing = barSpacing
        self.minimumBarHeight = minimumBarHeight
        self.animation = animation
        self.displayExponent = displayExponent
    }

    public var body: some View {
        GeometryReader { proxy in
            HStack(spacing: barSpacing) {
                ForEach(levels.bands.indices, id: \.self) { band in
                    bar(
                        level: displayed(levels.bands[band]),
                        peak: displayed(peakHold.peaks.indices.contains(band) ? peakHold.peaks[band] : 0),
                        height: proxy.size.height,
                    )
                }
            }
        }
        .animation(reduceMotion ? nil : animation, value: levels)
        .animation(reduceMotion ? nil : animation, value: peakHold)
        .onChange(of: levels, initial: true) { _, newLevels in
            guard showsPeaks else { return }
            // A silent frame means "at rest" — stopped, paused, reconnecting — so
            // the caps drop with the bars rather than hanging where the music was.
            if newLevels.bands.allSatisfy({ $0 == 0 }) {
                peakHold = PeakHold(bandCount: newLevels.bands.count)
            } else {
                peakHold.update(with: newLevels)
            }
        }
        .accessibilityHidden(true)
    }

    private func displayed(_ level: Float) -> CGFloat {
        CGFloat(pow(min(1, max(0, level)), displayExponent))
    }

    private var capHeight: CGFloat {
        max(1.5, minimumBarHeight * 0.6)
    }

    @ViewBuilder
    private func bar(level: CGFloat, peak: CGFloat, height: CGFloat) -> some View {
        switch style {
        case .bars:
            ZStack(alignment: .bottom) {
                Capsule()
                    .frame(height: max(minimumBarHeight, height * level))
                if showsPeaks, peak > 0 {
                    Capsule()
                        .frame(height: capHeight)
                        .opacity(0.55)
                        .offset(y: -min(height - capHeight, height * peak))
                }
            }
            .frame(height: height, alignment: .bottom)
        case .mirrored:
            ZStack {
                Capsule()
                    .frame(height: max(minimumBarHeight, height * level))
                if showsPeaks, peak > 0 {
                    let offset = min(height - capHeight, height * peak) / 2
                    Capsule()
                        .frame(height: capHeight)
                        .opacity(0.55)
                        .offset(y: -offset)
                    Capsule()
                        .frame(height: capHeight)
                        .opacity(0.55)
                        .offset(y: offset)
                }
            }
            .frame(height: height)
        }
    }
}

#Preview("Mirrored with peaks") {
    AudioLevelsView(levels: AudioLevels(bands: (0 ..< 24).map { Float(abs(sin(Double($0) / 3))) * 0.8 }))
        .frame(width: 260, height: 32)
        .foregroundStyle(.tint)
        .padding()
}

#Preview("Bars") {
    AudioLevelsView(
        levels: AudioLevels(bands: (0 ..< 24).map { Float($0) / 24 }),
        style: .bars,
    )
    .frame(width: 260, height: 32)
    .padding()
}
