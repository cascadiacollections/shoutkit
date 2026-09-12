import DesignSystem
import Playback
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
            artwork(playback, size: min(220, max(120, size.height - 64)))
            VStack(spacing: ShoutKitSpacing.medium) {
                titleBlock(playback: playback, station: station)
                statusBadge(playback)
                transportControls(playback: playback, station: station)
                routePicker
            }
            .frame(maxWidth: .infinity)
        }
        .padding(ShoutKitSpacing.large)
        .frame(minHeight: size.height)
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
