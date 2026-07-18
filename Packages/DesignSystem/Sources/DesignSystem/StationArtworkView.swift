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
    /// The point size used by station list rows (`StationRow`). Exposed so
    /// artwork prefetching can request the exact same decoded size — and thus
    /// the same cache key — the row will ask for.
    public static let listSize: CGFloat = 56

    /// The target decode size, in pixels, for list-row artwork at a given
    /// display scale — the value to pass to `ArtworkThumbnailLoader.prefetch`.
    public static func listPixelSize(displayScale: CGFloat) -> CGFloat {
        listSize * displayScale
    }

    private let artworkURL: URL?
    private let size: CGFloat
    private let cornerRadius: CGFloat
    private let isPlaying: Bool

    @State private var thumbnail: UIImage?
    /// The URL `thumbnail` was loaded for, so a reused row can drop the
    /// previous station's artwork instead of showing it under the new one.
    @State private var thumbnailURL: URL?
    @Environment(\.displayScale) private var displayScale

    public init(
        artworkURL: URL?,
        size: CGFloat = StationArtworkView.listSize,
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
                // A reused row must not keep showing the previous station's
                // artwork while the new one loads.
                if thumbnailURL != artworkURL {
                    thumbnail = nil
                    thumbnailURL = nil
                }
                let loaded = await ArtworkThumbnailLoader.thumbnail(
                    for: artworkURL,
                    maxPixelSize: size * displayScale
                )
                // A task cancelled by a URL change can still resume here with
                // a stale (or nil, from a cancelled fetch) result — don't let
                // it clobber the replacement task's image.
                guard Task.isCancelled == false else { return }
                thumbnail = loaded
                thumbnailURL = artworkURL
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
