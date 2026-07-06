import DesignSystem
import Playback
import RadioDirectory
import SwiftUI

/// A large editorial hero for the featured station.
struct SpotlightCard: View {
    let station: Station
    let phase: StationPlaybackPhase
    let onPlay: () -> Void

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
                .buttonStyle(.glassProminent)
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
    }

    private var isPlaying: Bool { phase == .playing }

    private var artworkOverlay: some View {
        GeometryReader { proxy in
            AsyncImage(url: station.artworkURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .opacity(0.35)
                    .overlay(LinearGradient(
                        colors: [.clear, .black.opacity(0.35)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            } placeholder: {
                Color.clear
            }
        }
    }
}
