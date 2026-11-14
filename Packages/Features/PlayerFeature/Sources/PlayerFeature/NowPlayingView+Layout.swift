import AudioLevelsUI
import DesignSystem
import Playback
import PlayerFeatureCore
import RadioDirectory
import SwiftUI

// Adaptive layouts for the full player. Kept separate from the controls so the
// main view remains readable and within the project's type-length budget.
extension NowPlayingView {
    func verticalContent(
        playback: PlaybackController,
        station: Station,
        size: CGSize,
    ) -> some View {
        VStack(spacing: ShoutKitSpacing.large) {
            grabberSpacer
            Spacer(minLength: ShoutKitSpacing.small)
            artwork(playback, size: verticalArtworkSize(in: size))
            titleBlock(playback: playback, station: station)
            levelMeter(playback)
            statusBadge(playback)
            Spacer(minLength: ShoutKitSpacing.small)
            transportControls(playback: playback, station: station)
            routePicker.padding(.bottom, ShoutKitSpacing.large)
        }
        .padding(.horizontal, ShoutKitSpacing.large)
        .frame(minHeight: size.height)
    }

    func compactContent(
        playback: PlaybackController,
        station: Station,
        size: CGSize,
    ) -> some View {
        HStack(spacing: ShoutKitSpacing.large) {
            artwork(playback, size: NowPlayingLayout.sideBySideArtworkSize(height: size.height))
            VStack(spacing: ShoutKitSpacing.medium) {
                titleBlock(playback: playback, station: station)
                levelMeter(playback)
                statusBadge(playback)
                transportControls(playback: playback, station: station)
                routePicker
            }
            .frame(maxWidth: .infinity)
        }
        .padding(ShoutKitSpacing.large)
        .frame(minHeight: size.height)
    }

    /// The live level meter (MIT `AudioLevelsUI`), fed by the engine's tap
    /// through ``PlaybackController/audioLevels(bandCount:)``. It meters only
    /// while playing with the scene active, and eases to rest on pause,
    /// buffering, reconnect and stop. Absent when the engine can't meter or the
    /// listener turned it off; Reduce Motion hides it inside the view.
    @ViewBuilder
    private func levelMeter(_ playback: PlaybackController) -> some View {
        if playback.supportsAudioLevels, settings?.isVisualizerEnabled ?? true {
            LiveAudioLevelsView(isActive: isPlaying(playback)) {
                playback.audioLevels()
            }
            .frame(maxWidth: 260)
            .frame(height: 28)
            .foregroundStyle(.tint)
        }
    }

    private func artwork(_ playback: PlaybackController, size: CGFloat) -> some View {
        HeroArtworkView(
            artworkURL: effectiveArtwork.primaryURL,
            fallbackArtworkURL: effectiveArtwork.fallbackURL,
            size: size,
            isPlaying: isPlaying(playback),
        )
    }

    private func verticalArtworkSize(in size: CGSize) -> CGFloat {
        let widthLimit = size.width - ShoutKitSpacing.large * 4
        let heightLimit = size.height * (dynamicTypeSize.isAccessibilitySize ? 0.25 : 0.38)
        return min(272, max(120, min(widthLimit, heightLimit)))
    }
}
