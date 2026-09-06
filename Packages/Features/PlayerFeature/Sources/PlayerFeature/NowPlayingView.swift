import DesignSystem
import Persistence
import Playback
import PlayerFeatureCore
import RadioDirectory
import SwiftUI

/// Full-screen Now Playing surface: large artwork, live metadata, transport
/// controls, favorite toggle, and AirPlay routing.
public struct NowPlayingView: View {
    @Environment(\.playbackController) private var playback
    @Environment(\.libraryStore) private var library
    // Not `private`: read by the sleep-timer controls, which live in
    // `NowPlayingView+SleepTimer.swift`.
    @Environment(\.sleepTimer) var sleepTimer
    @Environment(\.settingsStore) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// Control tint elected from the artwork palette so the transport
    /// controls sit in the same color world as the ambient backdrop.
    @State private var artworkAccent: Color?

    /// Identity for the transport row's glass shapes.
    ///
    /// Not `private`: the sleep timer's own glass lives in
    /// `NowPlayingView+SleepTimer.swift`, and a namespace only does anything if
    /// every shape in the cluster shares it.
    @Namespace var transportGlass

    /// The play/pause control's height. It grows with Dynamic Type instead of
    /// staying fixed: it is the primary control on this screen, and a listener
    /// who has turned text up has usually turned it up because targets at the
    /// default size are hard to hit. `.largeTitle` rather than `.body` so it
    /// scales at the rate of the display text it sits under, not body copy.
    @ScaledMetric(relativeTo: .largeTitle) private var playPauseHeight: CGFloat = 64

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

            // Balanced, not top-anchored. With a single `Spacer` above the
            // transport row, everything piled against the top of the sheet and
            // left one tall void in the middle of the screen — most visible on
            // a station with no track line, which is most live radio. A spacer
            // on each side splits that space, so the artwork sits where the eye
            // already is and the transport stays pinned to the bottom.
            Spacer(minLength: 0)

            HeroArtworkView(
                artworkURL: effectiveArtwork.primaryURL,
                fallbackArtworkURL: effectiveArtwork.fallbackURL,
                size: 272,
                isPlaying: isPlaying(playback)
            )

            titleBlock(playback: playback, station: station)

            statusBadge(playback)

            Spacer(minLength: 0)

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
            // One element, not two. Split, VoiceOver stops on the station name
            // and again on the track, and the rotor treats them as unrelated
            // headings — but they are one statement ("KEXP, Song — Artist"), and
            // the second line is meaningless without the first.
            .accessibilityElement(children: .combine)

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
    /// here; it gets the room, flanked by the two things people actually do
    /// while listening.
    ///
    /// The row is a `GlassEffectContainer` so the three controls are one glass
    /// cluster to the system rather than three unrelated ones: they sample the
    /// backdrop together, and — the reason this is here — the sleep timer's menu
    /// flies out of a registered glass shape instead of appearing over it.
    ///
    /// `spacing: 0`, not the row's own spacing. A container merges glass shapes
    /// that fall within `spacing` of each other, and at the 16 pt these controls
    /// sit apart that would fuse a circle, a wide capsule and a capsule into a
    /// single pill. Zero buys the shared rendering context and the morph without
    /// buying a redesign.
    private func transportControls(playback: PlaybackController, station: Station) -> some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: ShoutKitSpacing.medium) {
                favoriteButton(station: station)

                playPauseButton(playback)

                sleepTimerButton
            }
        }
    }

    /// A wide capsule rather than the circle this used to be.
    ///
    /// A circle sized for one glyph spends its width budget on the gaps beside
    /// it. Letting the primary control take the whole row between its two
    /// satellites roughly doubles the hit target on the thing people press most,
    /// at no cost to the other two — which are still 44 pt and still where they
    /// were. It is also what the current system players do, so the shape reads
    /// as "the main control" without having to be the largest circle on screen.
    private func playPauseButton(_ playback: PlaybackController) -> some View {
        Button {
            playback.togglePlayPause()
        } label: {
            playPauseIcon(playback)
                .font(.system(size: playPauseHeight * 0.42, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: playPauseHeight)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .glassEffectID(TransportGlassID.playPause, in: transportGlass)
        .accessibilityLabel(isPlaying(playback) ? "Pause" : "Play")
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
            .glassEffectID(TransportGlassID.favorite, in: transportGlass)
            .tint(library.isFavorite(station) ? (artworkAccent ?? .shoutKitHighlight) : .primary)
            .accessibilityLabel(library.isFavorite(station) ? "Remove favorite" : "Add favorite")
        } else {
            Color.clear.frame(width: 44, height: 44)
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

/// The transport row's glass shapes, named rather than spelled as string
/// literals — the sleep timer's is applied from another file, and a typo in a
/// `glassEffectID` fails by quietly doing nothing.
///
/// `nonisolated` is load-bearing. This package builds with
/// `.defaultIsolation(MainActor.self)`, so a bare `enum` here is MainActor-
/// isolated and so is its `Hashable` conformance — and `glassEffectID` takes
/// its ID as `Hashable & Sendable`, which a main-actor-isolated conformance
/// cannot satisfy. Without this the three call sites fail to compile with
/// `[#IsolatedConformances]`, and only in the iOS build: none of the host
/// package tests build this target.
nonisolated enum TransportGlassID: Hashable {
    case favorite
    case playPause
    case sleepTimer
}
