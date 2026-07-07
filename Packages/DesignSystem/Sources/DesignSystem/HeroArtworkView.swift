import SwiftUI

/// Now Playing hero artwork on a Liquid Glass ledge: the artwork tile sits on
/// a clear glass plate with a specular rim, and breathes with playback — full
/// size while playing, gently recessed while paused.
///
/// Directory artwork is usually a small favicon, so the tile caps its display
/// size at ~2.5× the bitmap's native points: a tiny icon renders as a crisp
/// badge centered on the plate instead of an upscaled blur. The plate keeps
/// the full footprint either way, so layout never jumps.
///
/// Honors Reduce Transparency (drops the glass plate) and Reduce Motion
/// (drops the spring scale).
public struct HeroArtworkView: View {
    /// How far beyond its native point size a bitmap may be stretched before
    /// it reads as blurry rather than merely soft.
    private static let maxUpscale: CGFloat = 2.5

    /// Smallest tile that still reads as a badge on the plate.
    private static let minTileSize: CGFloat = 120

    private let artworkURL: URL?
    private let size: CGFloat
    private let isPlaying: Bool

    @State private var artwork: LoadedArtwork?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(artworkURL: URL?, size: CGFloat = 280, isPlaying: Bool = false) {
        self.artworkURL = artworkURL
        self.size = size
        self.isPlaying = isPlaying
    }

    public var body: some View {
        tile
            .overlay { specularRim }
            .frame(width: size, height: size)
            .padding(ShoutKitSpacing.small)
            .background { glassPlate }
            .shadow(
                color: .black.opacity(isPlaying ? 0.35 : 0.20),
                radius: isPlaying ? 28 : 14,
                y: isPlaying ? 14 : 8
            )
            .scaleEffect(playbackScale)
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.75), value: isPlaying)
            .task(id: artworkURL) {
                let loaded = await ArtworkLoader.load(artworkURL)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    artwork = loaded
                }
            }
    }

    private var tile: some View {
        RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous)
            .fill(.tint.opacity(0.16))
            .overlay {
                if let artwork {
                    Image(uiImage: artwork.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    placeholder
                }
            }
            .frame(width: tileSize, height: tileSize)
            .clipShape(RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: tileSize * 0.34))
            .foregroundStyle(.tint)
    }

    /// Thin gradient border that reads as a light catch on the glass edge.
    private var specularRim: some View {
        RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.55), .white.opacity(0.06), .white.opacity(0.28)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .frame(width: tileSize, height: tileSize)
    }

    @ViewBuilder
    private var glassPlate: some View {
        if !reduceTransparency {
            Color.clear
                .glassEffect(
                    .clear,
                    in: RoundedRectangle(
                        cornerRadius: ShoutKitRadius.large + ShoutKitSpacing.small,
                        style: .continuous
                    )
                )
        }
    }

    private var tileSize: CGFloat {
        guard let artwork else { return size }
        let nativePoints = artwork.minPixelDimension / displayScale
        return min(size, max(Self.minTileSize, nativePoints * Self.maxUpscale))
    }

    private var tileCornerRadius: CGFloat {
        tileSize < 200 ? ShoutKitRadius.medium : ShoutKitRadius.large
    }

    private var playbackScale: CGFloat {
        if reduceMotion { return 1 }
        return isPlaying ? 1 : 0.85
    }
}

#Preview {
    ZStack {
        AmbientArtworkBackdrop(artworkURL: nil)
        VStack(spacing: 40) {
            HeroArtworkView(artworkURL: nil, size: 200, isPlaying: true)
            HeroArtworkView(artworkURL: nil, size: 200, isPlaying: false)
        }
    }
    .tint(.shoutKitAccent)
}
