import DesignSystem
import Persistence
import Playback
import RadioDirectory
import SwiftUI

/// Compact glass now-playing bar designed to sit in the tab bar bottom accessory.
/// Tapping the bar (outside the controls) expands the full Now Playing screen.
/// Shows a "Not Playing" placeholder when idle so the accessory can stay attached
/// (detaching it resets the TabView's structural identity).
public struct MiniPlayerView: View {
    @Environment(\.playbackController) private var playback
    @Environment(\.libraryStore) private var library

    private let onExpand: () -> Void

    public init(onExpand: @escaping () -> Void) {
        self.onExpand = onExpand
    }

    public var body: some View {
        if let playback, let station = playback.currentStation {
            content(playback: playback, station: station)
        } else {
            idlePlaceholder
        }
    }

    private var idlePlaceholder: some View {
        HStack(spacing: ShoutKitSpacing.small) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(.secondary)

            Text("Not Playing")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, ShoutKitSpacing.medium)
        .padding(.vertical, ShoutKitSpacing.extraSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Not playing")
    }

    private func content(playback: PlaybackController, station: Station) -> some View {
        HStack(spacing: ShoutKitSpacing.small) {
            StationArtworkView(
                artworkURL: station.artworkURL,
                size: 40,
                cornerRadius: ShoutKitRadius.small,
                isPlaying: isPlaying(playback)
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(station.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(secondaryLine(playback))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: ShoutKitSpacing.small)

            if let library {
                Button {
                    library.toggleFavorite(station)
                } label: {
                    Image(systemName: library.isFavorite(station) ? "heart.fill" : "heart")
                        .foregroundStyle(library.isFavorite(station) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(library.isFavorite(station) ? "Remove favorite" : "Add favorite")
            }

            Button {
                playback.togglePlayPause()
            } label: {
                playPauseIcon(playback)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying(playback) ? "Pause" : "Play")
        }
        .padding(.horizontal, ShoutKitSpacing.small)
        .padding(.vertical, ShoutKitSpacing.extraSmall)
        .contentShape(Rectangle())
        .onTapGesture(perform: onExpand)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open Now Playing", onExpand)
    }

    @ViewBuilder
    private func playPauseIcon(_ playback: PlaybackController) -> some View {
        switch playback.state {
        case .loading, .buffering:
            ProgressView().controlSize(.small)
        case .playing:
            Image(systemName: "pause.fill")
        default:
            Image(systemName: "play.fill")
        }
    }

    private func isPlaying(_ playback: PlaybackController) -> Bool {
        if case .playing = playback.state { return true }
        return false
    }

    private func secondaryLine(_ playback: PlaybackController) -> String {
        switch playback.state {
        case .loading, .buffering:
            return "Connecting…"
        case .failed:
            return "Tap to retry"
        default:
            if playback.isAdPlaying {
                return "Ad detected • open player for ambient"
            }
            if let track = playback.nowPlaying, let title = track.title {
                if let artist = track.artist { return "\(title) — \(artist)" }
                return title
            }
            return playback.currentStation?.genre ?? "Live radio"
        }
    }
}
