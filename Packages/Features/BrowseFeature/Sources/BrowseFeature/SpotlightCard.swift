import DesignSystem
import Playback
import RadioDirectory
import SwiftUI
import UIKit

/// A large editorial hero for the featured station.
struct SpotlightCard: View {
    /// Decode ceiling for the backdrop artwork. It renders full-bleed but at
    /// 35% opacity under a gradient scrim — 900 px stays crisp even on iPad
    /// widths while keeping an oversized favicon from decoding at native size.
    private static let maxArtworkPixels: CGFloat = 900

    let station: Station
    let phase: StationPlaybackPhase
    let onPlay: () -> Void

    @State private var artwork: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient.shoutKitSpotlight

            artworkOverlay

            VStack(alignment: .leading, spacing: ShoutKitSpacing.small) {
                Text("Featured Station")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .textCase(.uppercase)

                Text(station.name)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(station.genre)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))

                Button(action: onPlay) {
                    Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, ShoutKitSpacing.small)
                }
                .shoutKitGlassProminentButtonStyle()
                .tint(.white)
                .foregroundStyle(Color.shoutKitAccent)
                .padding(.top, ShoutKitSpacing.extraSmall)
            }
            .padding(ShoutKitSpacing.large)
        }
        // Min height, not fixed: the title/genre must not clip at accessibility
        // Dynamic Type sizes.
        .frame(maxWidth: .infinity, minHeight: 220)
        .clipShape(RoundedRectangle(cornerRadius: ShoutKitRadius.large, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Featured station, \(station.name), \(station.genre)")
        .task(id: station.artworkURL) {
            artwork = await ArtworkThumbnailLoader.thumbnail(
                for: station.artworkURL,
                maxPixelSize: Self.maxArtworkPixels
            )
        }
    }

    private var isPlaying: Bool { phase == .playing }

    @ViewBuilder
    private var artworkOverlay: some View {
        if let artwork {
            GeometryReader { proxy in
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .opacity(0.35)
                    .overlay(LinearGradient(
                        colors: [.clear, .black.opacity(0.35)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            }
        }
    }
}
