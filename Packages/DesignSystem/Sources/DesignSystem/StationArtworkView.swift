import RadioDirectory
import SwiftUI
import UIKit

/// Async-loading station artwork with a graceful glass placeholder and an optional
/// "now playing" overlay.
///
/// Artwork loads through ``ArtworkThumbnailLoader`` rather than `AsyncImage`,
/// so the decoded bitmap is sized to this view (`size` × display scale)
/// instead of the source's native resolution, and repeated appearances in
/// lazy lists hit a pressure-evicting `NSCache` instead of re-decoding.
public struct StationArtworkView: View {
    private let artworkURL: URL?
    private let size: CGFloat
    private let cornerRadius: CGFloat
    private let isPlaying: Bool

    @State private var thumbnail: UIImage?
    @Environment(\.displayScale) private var displayScale

    public init(
        artworkURL: URL?,
        size: CGFloat = 56,
        cornerRadius: CGFloat = ShoutKitRadius.small,
        isPlaying: Bool = false
    ) {
        self.artworkURL = artworkURL
        self.size = size
        self.cornerRadius = cornerRadius
        self.isPlaying = isPlaying
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.tint.opacity(0.16))
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    placeholder
                }
            }
            .overlay {
                if isPlaying {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.black.opacity(0.35))
                        PlayingIndicator(color: .white, isAnimating: true)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
            }
            .task(id: artworkURL) {
                thumbnail = await ArtworkThumbnailLoader.thumbnail(
                    for: artworkURL,
                    maxPixelSize: size * displayScale
                )
            }
    }

    private var placeholder: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: size * 0.34))
            .foregroundStyle(.tint)
    }
}

#Preview {
    HStack {
        StationArtworkView(artworkURL: nil)
        StationArtworkView(artworkURL: nil, isPlaying: true)
    }
    .padding()
    .tint(.shoutKitAccent)
}
