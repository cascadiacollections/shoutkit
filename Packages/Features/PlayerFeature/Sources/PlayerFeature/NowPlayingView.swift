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
    @Environment(\.openURL) private var openURL

    /// Control tint elected from the artwork palette so the transport
    /// controls sit in the same color world as the ambient backdrop.
    @State private var artworkAccent: Color?

    public init() {}

    public var body: some View {
        ZStack {
            AmbientArtworkBackdrop(
                artworkURL: effectiveArtwork.primaryURL,
                fallbackArtworkURL: effectiveArtwork.fallbackURL
            )

            if let playback, let station = playback.currentStation {
                content(playback: playback, station: station)
            } else {
                ContentUnavailableView("Nothing Playing", systemImage: "dot.radiowaves.left.and.right")
            }
        }
        .presentationDragIndicator(.visible)
        .tint(accent)
        .onChange(of: artworkLoadRequest) { _, _ in
            artworkAccent = nil
        }
        .task(id: artworkLoadRequest) {
            let loaded = await ArtworkLoadPolicy.load(artworkLoadRequest) { url in
                await ArtworkLoader.load(url)
            }
            // The store's await isn't cancellation-responsive, so a task
            // cancelled by a URL change still resumes here — without this
            // guard it would overwrite the new URL's accent with the old.
            guard Task.isCancelled == false else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                artworkAccent = loaded?.accentColor
            }
        }
    }

    private var effectiveArtwork: EffectiveArtworkSelection {
        PlayerFeature.effectiveArtworkSelection(
            settings: settings,
            playback: playback,
            station: playback?.currentStation
        )
    }

    private var artworkLoadRequest: ArtworkLoadRequest {
        ArtworkLoadRequest(
            primaryURL: effectiveArtwork.primaryURL,
            fallbackURL: effectiveArtwork.fallbackURL
        )
    }

    /// The Apple Music link for the current track, gated on the same privacy
    /// toggle as artwork so opting out of catalog lookups removes the "View in
    /// Apple Music" affordance immediately — not just on the next track — even
    /// though a link was already resolved for what's playing.
    private var appleMusicURL: URL? {
        guard settings?.isAlbumArtEnabled == true else { return nil }
        return playback?.appleMusicURL
    }

    private var accent: Color {
        artworkAccent ?? .shoutKitAccent
    }

    private func content(playback: PlaybackController, station: Station) -> some View {
        VStack(spacing: ShoutKitSpacing.large) {
            grabberSpacer

            HeroArtworkView(
                artworkURL: effectiveArtwork.primaryURL,
                fallbackArtworkURL: effectiveArtwork.fallbackURL,
                size: 272,
                isPlaying: isPlaying(playback)
            )
            .padding(.top, ShoutKitSpacing.medium)

            titleBlock(playback: playback, station: station)

            statusBadge(playback)

            Spacer()

            transportControls(playback: playback, station: station)

            routePicker
                .padding(.bottom, ShoutKitSpacing.large)
        }
        .padding(.horizontal, ShoutKitSpacing.large)
        .frame(maxWidth: .infinity)
    }

    private var grabberSpacer: some View {
        Color.clear.frame(height: ShoutKitSpacing.small)
    }

    /// Station and track, leading-aligned with an overflow menu on the trailing
    /// edge — the Now Playing convention across Apple's own players. Centered
    /// text with no anchor is fine for one line and starts drifting as soon as a
    /// long station name and a long track title disagree about how many they
    /// need.
    private func titleBlock(playback: PlaybackController, station: Station) -> some View {
        HStack(alignment: .top, spacing: ShoutKitSpacing.small) {
            VStack(alignment: .leading, spacing: ShoutKitSpacing.extraSmall) {
                Text(station.name)
                    .font(.title2.bold())
                    .lineLimit(2)

                Text(trackLine(playback) ?? station.genre)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            overflowMenu(playback: playback)
        }
    }

    /// The actions that aren't playback: leaving for Apple Music, and ending the
    /// stream outright.
    ///
    /// Stop used to sit in the transport row beside play/pause, which put a
    /// control that dismisses the whole screen one 8 pt gap from the one people
    /// reach for constantly — and gave a live-radio player a three-button
    /// transport where two of the buttons do overlapping things.
    private func overflowMenu(playback: PlaybackController) -> some View {
        Menu {
            if let appleMusicURL {
                Button("View in Apple Music", systemImage: "music.note") {
                    openURL(appleMusicURL)
                }
            }
            Button("Stop", systemImage: "stop.fill", role: .destructive) {
                playback.stop()
                dismiss()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("More")
    }

    private var routePicker: some View {
        RoutePickerView(tintColor: .secondaryLabel, activeTintColor: UIColor(accent))
            .frame(width: 44, height: 44)
            .accessibilityLabel("AirPlay and output devices")
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
        case let .failed(error):
            Text(error.userMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        case .paused, .idle:
            Color.clear.frame(height: 1)
        }
    }

    /// Favorite · play/pause · sleep timer. A live stream has nothing to scrub
    /// and nothing to skip to, so play/pause is the only true transport control
    /// here; it gets the size and the center, flanked by the two things people
    /// actually do while listening.
    private func transportControls(playback: PlaybackController, station: Station) -> some View {
        HStack(spacing: ShoutKitSpacing.extraLarge) {
            favoriteButton(station: station)

            Button {
                playback.togglePlayPause()
            } label: {
                playPauseIcon(playback)
                    .font(.system(size: 34, weight: .bold))
                    .frame(width: 76, height: 76)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .accessibilityLabel(isPlaying(playback) ? "Pause" : "Play")

            sleepTimerButton
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
            .buttonStyle(.glass)
            // Capsule, not circle: the running timer's label carries a countdown
            // and has to be allowed to grow.
            .buttonBorderShape(.capsule)
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
