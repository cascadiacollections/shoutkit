import ActivityKit
import NowPlayingActivityCore
import SwiftUI
import UIKit
import WidgetKit

/// Lock screen banner + Dynamic Island presentation for the now-playing stream.
/// Artwork is handed over out-of-band: the app stages a downsampled bitmap in the
/// shared App Group container (see `LiveActivityArtworkStore`) and the content
/// state carries only its token, since Live Activity views can't fetch network
/// images and the state payload is too small to hold one. When no art is staged
/// yet, each surface falls back to a playback glyph.
struct NowPlayingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ArtworkTile(
                        token: context.state.artworkToken,
                        fallbackSymbol: playbackSymbol(context),
                        size: 38,
                        cornerRadius: 9
                    )
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
                ArtworkTile(
                    token: context.state.artworkToken,
                    fallbackSymbol: "dot.radiowaves.left.and.right",
                    size: 22,
                    cornerRadius: 5
                )
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
            ArtworkTile(
                token: context.state.artworkToken,
                fallbackSymbol: context.state.isPlaying ? "waveform" : "pause.fill",
                size: 40,
                cornerRadius: 10
            )

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

/// Renders the staged artwork for a token, falling back to a tinted glyph on a
/// quaternary tile when nothing is staged yet (or the file can't be read).
private struct ArtworkTile: View {
    let token: String?
    let fallbackSymbol: String
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image = stagedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var stagedImage: UIImage? {
        guard let token,
              let url = LiveActivityArtworkStore.fileURL(forToken: token) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}
