import ActivityKit
import NowPlayingActivityCore
import SwiftUI
import WidgetKit

/// Lock screen banner + Dynamic Island presentation for the now-playing stream.
/// Text-only by design: Live Activity views cannot load network images, so
/// artwork is scoped out rather than half-shipped (see NowPlayingActivityCore).
struct NowPlayingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: playbackSymbol(context))
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.stationName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(trackLine(context) ?? context.attributes.genre)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Label(context.state.isPlaying ? "Live" : "Paused",
                          systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.tint)
            } compactTrailing: {
                Image(systemName: playbackSymbol(context))
                    .foregroundStyle(.tint)
            } minimal: {
                Image(systemName: playbackSymbol(context))
                    .foregroundStyle(.tint)
            }
        }
    }

    private func playbackSymbol(_ context: ActivityViewContext<NowPlayingActivityAttributes>) -> String {
        context.state.isPlaying ? "waveform" : "pause.fill"
    }

    private func trackLine(_ context: ActivityViewContext<NowPlayingActivityAttributes>) -> String? {
        guard let title = context.state.trackTitle else { return nil }
        if let artist = context.state.artist {
            return "\(title) — \(artist)"
        }
        return title
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<NowPlayingActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.stationName)
                    .font(.headline)
                    .lineLimit(1)

                Text(trackLine ?? context.attributes.genre)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Label(context.state.isPlaying ? "Live" : "Paused",
                  systemImage: "dot.radiowaves.left.and.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
        }
        .padding(14)
    }

    private var trackLine: String? {
        guard let title = context.state.trackTitle else { return nil }
        if let artist = context.state.artist {
            return "\(title) — \(artist)"
        }
        return title
    }
}
