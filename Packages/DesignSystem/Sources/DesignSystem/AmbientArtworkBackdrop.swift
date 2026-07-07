import SwiftUI

/// Full-bleed "acrylic" backdrop for hero surfaces, under a legibility
/// material so Liquid Glass controls and text read correctly on top.
///
/// Directory artwork is usually a small favicon, so the wash adapts to what
/// the bitmap can actually support: genuinely large artwork (≥512px) renders
/// as a classic blurred image wash, while small artwork becomes a 3×3
/// `MeshGradient` of its dominant colors — resolution-independent, so a tiny
/// icon still yields a rich multi-tone backdrop instead of a smeared solid.
///
/// Falls back to the brand spotlight gradient while artwork is loading or
/// unavailable, and to a flat brand background when the user has
/// Reduce Transparency enabled.
public struct AmbientArtworkBackdrop: View {
    /// Artwork at or above this pixel size has enough detail for a direct
    /// blur wash; anything smaller uses the color mesh.
    private static let blurWashMinPixels: CGFloat = 512

    private let artworkURL: URL?

    @State private var artwork: LoadedArtwork?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(artworkURL: URL?) {
        self.artworkURL = artworkURL
    }

    public var body: some View {
        ZStack {
            if reduceTransparency {
                Color.shoutKitBackground
            } else {
                brandFallback
                ambientWash
                Rectangle()
                    .fill(.ultraThinMaterial)
                legibilityScrim
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task(id: artworkURL) {
            let loaded = await ArtworkLoader.load(artworkURL)
            withAnimation(.easeInOut(duration: 0.6)) {
                artwork = loaded
            }
        }
    }

    private var brandFallback: some View {
        LinearGradient.shoutKitSpotlight
            .opacity(0.35)
    }

    @ViewBuilder
    private var ambientWash: some View {
        if let artwork {
            Group {
                if artwork.minPixelDimension >= Self.blurWashMinPixels {
                    blurWash(artwork.image)
                } else if artwork.paletteGrid.count == 9 {
                    paletteMesh(artwork.paletteGrid)
                }
            }
            .transition(.opacity)
        }
    }

    private func blurWash(_ image: UIImage) -> some View {
        Color.clear
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    // Overscan so the blur has no vignetted edges.
                    .scaleEffect(1.4)
                    .blur(radius: 60, opaque: true)
                    .saturation(1.5)
            }
            .clipped()
    }

    private func paletteMesh(_ colors: [Color]) -> some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5, 0.5], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ],
            colors: colors
        )
    }

    private var legibilityScrim: some View {
        LinearGradient(
            colors: [.black.opacity(0.05), .black.opacity(0.30)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

#Preview {
    ZStack {
        AmbientArtworkBackdrop(artworkURL: nil)
        Text("Fallback gradient")
    }
}
