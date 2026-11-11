import AudioLevels
import SwiftUI

/// An ``AudioLevelsView`` that subscribes to a level stream for itself, and only
/// while it is worth it: `isActive` (typically "playing, and the user wants a
/// meter") and the scene in the foreground. When either stops being true the
/// task ends — which ends the stream, which is the engine's cue to remove its
/// tap — and the bars ease to rest rather than snapping flat.
///
/// ```swift
/// LiveAudioLevelsView(isActive: player.isPlaying) {
///     player.makeLevelStream()   // e.g. an AudioLevelMeter's `levels`
/// }
/// .frame(height: 28)
/// ```
///
/// Hidden entirely under Reduce Motion by default, per the audio levels spec:
/// the meter is decoration, and its motion is the whole of it.
public struct LiveAudioLevelsView: View {
    /// How long bars take to settle when metering stops.
    public static let restAnimation = Animation.easeOut(duration: 0.6)

    private let isActive: Bool
    private let displayBandCount: Int?
    private let style: AudioLevelsView.Style
    private let showsPeaks: Bool
    private let barSpacing: CGFloat
    private let minimumBarHeight: CGFloat
    private let hidesForReducedMotion: Bool
    private let autoGains: Bool
    private let source: () -> AsyncStream<AudioLevels>

    @State private var levels: AudioLevels?
    @State private var isResting = true
    @State private var autoGain = AutoGain()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - displayBandCount: Fold incoming frames to this many bars (see
    ///     ``AudioLevels/resampled(to:)``) — for a compact meter fed by the same
    ///     full-resolution stream. `nil` draws every band.
    ///   - autoGains: Scale frames with ``AutoGain`` so quiet and loud streams
    ///     both fill the meter. On by default.
    ///   - source: Called each time metering starts; must return a fresh stream.
    public init(
        isActive: Bool,
        displayBandCount: Int? = nil,
        style: AudioLevelsView.Style = .mirrored,
        showsPeaks: Bool = true,
        barSpacing: CGFloat = 3,
        minimumBarHeight: CGFloat = 3,
        hidesForReducedMotion: Bool = true,
        autoGains: Bool = true,
        source: @escaping () -> AsyncStream<AudioLevels>,
    ) {
        self.isActive = isActive
        self.displayBandCount = displayBandCount
        self.style = style
        self.showsPeaks = showsPeaks
        self.barSpacing = barSpacing
        self.minimumBarHeight = minimumBarHeight
        self.hidesForReducedMotion = hidesForReducedMotion
        self.autoGains = autoGains
        self.source = source
    }

    public var body: some View {
        if hidesForReducedMotion == false || reduceMotion == false {
            AudioLevelsView(
                levels: levels ?? .silent(bandCount: displayBandCount ?? AudioLevels.defaultBandCount),
                style: style,
                showsPeaks: showsPeaks,
                barSpacing: barSpacing,
                minimumBarHeight: minimumBarHeight,
                animation: isResting ? Self.restAnimation : AudioLevelsView.defaultAnimation,
            )
            .task(id: isMetering) {
                await meter()
            }
        }
    }

    private var isMetering: Bool {
        isActive && scenePhase == .active
    }

    private func meter() async {
        guard isMetering else {
            isResting = true
            levels = levels.map { .silent(bandCount: $0.bands.count) }
            return
        }
        isResting = false
        // Ends when this task is cancelled (`isMetering` flipped, or the view
        // left the hierarchy), which ends the stream.
        for await frame in source() {
            let scaled = autoGains ? autoGain.apply(to: frame) : frame
            levels = displayBandCount.map { scaled.resampled(to: $0) } ?? scaled
        }
    }
}
