import SwiftUI

/// A small animated equalizer that signals a station is currently playing.
public struct PlayingIndicator: View {
    public var color: Color
    public var isAnimating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    public init(color: Color = .white, isAnimating: Bool = true) {
        self.color = color
        self.isAnimating = isAnimating
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: isPaused)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: barHeight(index: index, time: time))
                }
            }
        }
        .frame(width: 16, height: 14, alignment: .bottom)
        .accessibilityHidden(true)
    }

    /// Rest the equalizer whenever the caller isn't playing, Reduce Motion is on,
    /// or the scene isn't foreground-active. The last case matters most for
    /// battery: a radio app spends hours backgrounded/locked, where an ~8 fps
    /// `sin()` re-layout would be pure waste no one can see.
    private var isPaused: Bool {
        !isAnimating || reduceMotion || scenePhase != .active
    }

    private func barHeight(index: Int, time: TimeInterval) -> CGFloat {
        guard !isPaused else { return 6 }
        let phase = time * 6 + Double(index) * 1.7
        let normalized = (sin(phase) + 1) / 2 // 0...1
        return 4 + normalized * 10
    }
}

#Preview {
    PlayingIndicator(color: .accentColor)
        .padding()
}
