import SwiftUI

/// A small animated equalizer that signals a station is currently playing.
public struct PlayingIndicator: View {
    public var color: Color
    public var isAnimating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(color: Color = .white, isAnimating: Bool = true) {
        self.color = color
        self.isAnimating = isAnimating
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !isAnimating || reduceMotion)) { timeline in
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

    private func barHeight(index: Int, time: TimeInterval) -> CGFloat {
        guard isAnimating && !reduceMotion else { return 6 }
        let phase = time * 6 + Double(index) * 1.7
        let normalized = (sin(phase) + 1) / 2 // 0...1
        return 4 + normalized * 10
    }
}

#Preview {
    PlayingIndicator(color: .accentColor)
        .padding()
}
