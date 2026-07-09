import DesignSystem
import Persistence
import Playback
import RadioDirectory
import SwiftUI

/// Full-screen Now Playing surface: large artwork, live metadata, transport
/// controls, favorite toggle, and AirPlay routing.
public struct NowPlayingView: View {
    @Environment(\.playbackController) private var playback
    @Environment(\.libraryStore) private var library
    @Environment(\.sleepTimer) private var sleepTimer
    @Environment(\.settingsStore) private var settings
    @Environment(\.dismiss) private var dismiss

    /// Control tint elected from the artwork palette so the transport
    /// controls sit in the same color world as the ambient backdrop.
    @State private var artworkAccent: Color?

    public init() {}

    public var body: some View {
        ZStack {
            AmbientArtworkBackdrop(artworkURL: effectiveArtworkURL)

            if let playback, let station = playback.currentStation {
                content(playback: playback, station: station)
            } else {
                ContentUnavailableView("Nothing Playing", systemImage: "dot.radiowaves.left.and.right")
            }
        }
        .presentationDragIndicator(.visible)
        .tint(accent)
        .task(id: effectiveArtworkURL) {
            let loaded = await ArtworkLoader.load(effectiveArtworkURL)
            withAnimation(.easeInOut(duration: 0.6)) {
                artworkAccent = loaded?.accentColor
            }
        }
    }

    /// The artwork URL to display: album art when the feature is enabled and a
    /// URL has been resolved, otherwise the station's own artwork.
    private var effectiveArtworkURL: URL? {
        if settings?.isAlbumArtEnabled == true, let albumArt = playback?.albumArtURL {
            return albumArt
        }
        return playback?.currentStation?.artworkURL
    }

    private var accent: Color {
        artworkAccent ?? .shoutKitAccent
    }

    private func content(playback: PlaybackController, station: Station) -> some View {
        VStack(spacing: ShoutKitSpacing.large) {
            grabberSpacer

            HeroArtworkView(
                artworkURL: effectiveArtworkURL,
                size: 272,
                isPlaying: isPlaying(playback)
            )
            .padding(.top, ShoutKitSpacing.medium)

            VStack(spacing: ShoutKitSpacing.extraSmall) {
                Text(station.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(trackLine(playback) ?? station.genre)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, ShoutKitSpacing.large)

            statusBadge(playback)

            Spacer()

            transportControls(playback: playback, station: station)

            bottomBar
                .padding(.bottom, ShoutKitSpacing.large)
        }
        .padding(.horizontal, ShoutKitSpacing.large)
        .frame(maxWidth: .infinity)
    }

    private var grabberSpacer: some View {
        Color.clear.frame(height: ShoutKitSpacing.small)
    }

    @ViewBuilder
    private func statusBadge(_ playback: PlaybackController) -> some View {
        switch playback.state {
        case .loading, .buffering:
            Label("Connecting", systemImage: "waveform")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        case .playing:
            Label("Live", systemImage: "dot.radiowaves.left.and.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
        case let .failed(message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        case .paused, .idle:
            Color.clear.frame(height: 1)
        }
    }

    private func transportControls(playback: PlaybackController, station: Station) -> some View {
        HStack(spacing: ShoutKitSpacing.extraLarge) {
            Button {
                playback.stop()
                dismiss()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title2)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Stop")

            Button {
                playback.togglePlayPause()
            } label: {
                playPauseIcon(playback)
                    .font(.system(size: 34, weight: .bold))
                    .frame(width: 72, height: 72)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .accessibilityLabel(isPlaying(playback) ? "Pause" : "Play")

            favoriteButton(station: station)
        }
    }

    @ViewBuilder
    private func favoriteButton(station: Station) -> some View {
        if let library {
            Button {
                library.toggleFavorite(station)
            } label: {
                Image(systemName: library.isFavorite(station) ? "heart.fill" : "heart")
                    .font(.title2)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(library.isFavorite(station) ? (artworkAccent ?? .shoutKitHighlight) : .primary)
            .accessibilityLabel(library.isFavorite(station) ? "Remove favorite" : "Add favorite")
        } else {
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var bottomBar: some View {
        HStack {
            sleepTimerButton
            Spacer()
            RoutePickerView(tintColor: .secondaryLabel, activeTintColor: UIColor(accent))
                .frame(width: 44, height: 44)
                .accessibilityLabel("AirPlay and output devices")
            Spacer()
            // Balances the timer button so AirPlay stays centered.
            Color.clear.frame(width: 44, height: 44)
        }
    }

    @ViewBuilder
    private var sleepTimerButton: some View {
        if let sleepTimer {
            Menu {
                if sleepTimer.isActive {
                    Button("Cancel Timer", systemImage: "moon.zzz", role: .destructive) {
                        sleepTimer.cancel()
                    }
                }
                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                    Button("\(minutes) minutes") {
                        sleepTimer.start(duration: TimeInterval(minutes * 60))
                    }
                }
            } label: {
                sleepTimerLabel(sleepTimer)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(sleepTimer.isActive ? "Sleep timer running" : "Sleep timer")
        } else {
            Color.clear.frame(width: 44, height: 44)
        }
    }

    @ViewBuilder
    private func sleepTimerLabel(_ sleepTimer: SleepTimer) -> some View {
        if sleepTimer.isActive {
            // Live countdown derived from fireDate; the model never ticks.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                HStack(spacing: 4) {
                    Image(systemName: "moon.zzz.fill")
                    if let remaining = sleepTimer.remaining(asOf: timeline.date) {
                        Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))
                            .font(.footnote.monospacedDigit())
                    }
                }
                .foregroundStyle(.tint)
            }
        } else {
            Image(systemName: "moon.zzz")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func playPauseIcon(_ playback: PlaybackController) -> some View {
        switch playback.state {
        case .loading, .buffering:
            ProgressView().controlSize(.large)
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

    private func trackLine(_ playback: PlaybackController) -> String? {
        guard let track = playback.nowPlaying, let title = track.title else { return nil }
        if let artist = track.artist { return "\(title) — \(artist)" }
        return title
    }
}
