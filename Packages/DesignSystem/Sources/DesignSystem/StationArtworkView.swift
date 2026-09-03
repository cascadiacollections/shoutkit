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
///
/// Two sizings. A **fixed** one for rows and the mini-player, where the point
/// size is known and is also the decode size. And a **flexible** one for poster
/// grids, where the tile width is whatever the grid hands the cell: the view
/// stays square and fills the width, and decoding is sized from an explicit
/// `decodeSize` hint instead. The hint is deliberately not the exact rendered
/// width — an adaptive grid's cell width is a fraction of the container and
/// isn't known until layout, and a decode size that varied per device would
/// fragment the thumbnail cache by a few points for no visible gain.
public struct StationArtworkView: View {
    /// The point size used by station list rows (`StationRow`). Exposed so
    /// artwork prefetching can request the exact same decoded size — and thus
    /// the same cache key — the row will ask for.
    public static let listSize: CGFloat = 56

    /// The decode size used by poster tiles in ``ShoutKitLayout/artworkColumns``.
    /// Sized to the widest cell that layout produces, so the bitmap is
    /// downscaled at worst and never upscaled.
    public static let posterDecodeSize: CGFloat = 240

    /// The target decode size, in pixels, for list-row artwork at a given
    /// display scale — the value to pass to `ArtworkThumbnailLoader.prefetch`.
    public static func listPixelSize(displayScale: CGFloat) -> CGFloat {
        listSize * displayScale
    }

    /// The target decode size, in pixels, for poster-tile artwork.
    public static func posterPixelSize(displayScale: CGFloat) -> CGFloat {
        posterDecodeSize * displayScale
    }

    fileprivate enum Sizing {
        /// A known square edge, used for both layout and decoding.
        case fixed(CGFloat)
        /// Fills the cell's width and stays square; decodes at `decode` points.
        case flexible(decode: CGFloat)

        var decodeSize: CGFloat {
            switch self {
            case let .fixed(size): size
            case let .flexible(decode): decode
            }
        }
    }

    /// How small a decoded bitmap may be, as a fraction of the pixels the tile
    /// wants, before it is inset over a generated backdrop instead of stretched
    /// to fill. Well below 1 on purpose: only genuinely tiny logos qualify, so a
    /// merely-imperfect image is still shown the normal way.
    private static let lowResolutionFraction: CGFloat = 0.7

    private let artworkURL: URL?
    private let fallbackArtworkURL: URL?
    private let sizing: Sizing
    private let cornerRadius: CGFloat
    private let isPlaying: Bool
    /// Identity for the generated placeholder — the station name. `nil` keeps
    /// the old generic glyph, which is right for surfaces with no name to show
    /// (track artwork, previews).
    private let placeholderSeed: String?

    @State private var thumbnail: UIImage?
    /// The URL `thumbnail` was loaded for, so a reused row can drop the
    /// previous station's artwork instead of showing it under the new one.
    @State private var thumbnailURL: URL?
    @Environment(\.displayScale) private var displayScale

    public init(
        artworkURL: URL?,
        fallbackArtworkURL: URL? = nil,
        size: CGFloat = StationArtworkView.listSize,
        cornerRadius: CGFloat = ShoutKitRadius.small,
        isPlaying: Bool = false,
        placeholderSeed: String? = nil
    ) {
        self.artworkURL = artworkURL
        self.fallbackArtworkURL = fallbackArtworkURL
        sizing = .fixed(size)
        self.cornerRadius = cornerRadius
        self.isPlaying = isPlaying
        self.placeholderSeed = placeholderSeed
    }

    /// Square artwork that fills the width it is given — the poster-grid tile.
    public static func filling(
        artworkURL: URL?,
        fallbackArtworkURL: URL? = nil,
        cornerRadius: CGFloat = ShoutKitRadius.card,
        isPlaying: Bool = false,
        decodeSize: CGFloat = StationArtworkView.posterDecodeSize,
        placeholderSeed: String? = nil
    ) -> StationArtworkView {
        StationArtworkView(
            artworkURL: artworkURL,
            fallbackArtworkURL: fallbackArtworkURL,
            sizing: .flexible(decode: decodeSize),
            cornerRadius: cornerRadius,
            isPlaying: isPlaying,
            placeholderSeed: placeholderSeed
        )
    }

    private init(
        artworkURL: URL?,
        fallbackArtworkURL: URL?,
        sizing: Sizing,
        cornerRadius: CGFloat,
        isPlaying: Bool,
        placeholderSeed: String?
    ) {
        self.artworkURL = artworkURL
        self.fallbackArtworkURL = fallbackArtworkURL
        self.sizing = sizing
        self.cornerRadius = cornerRadius
        self.isPlaying = isPlaying
        self.placeholderSeed = placeholderSeed
    }

    public var body: some View {
        // `Color.clear` as the sizing base, with everything else in overlays.
        // A `scaledToFill` image is deliberately larger than the size proposed
        // to it, so making it the root let it drive layout and the tiles grew
        // past the grid's padding to the screen edges. A Color accepts the
        // proposal exactly, and an overlay is bounded by its base.
        Color.clear
            .overlay { artworkLayer }
            .overlay { playingLayer }
            .modifier(SquareSizing(sizing: sizing))
            .clipShape(shape)
            .overlay { shape.stroke(.white.opacity(0.12), lineWidth: 0.5) }
            .onChange(of: artworkRequest) { _, _ in
                thumbnail = nil
                thumbnailURL = nil
            }
            .task(id: artworkRequest) { await loadArtwork() }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder
    private var artworkLayer: some View {
        if let image = resolvedThumbnail {
            if isLowResolution(image) {
                lowResolutionArtwork(image)
            } else {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        } else {
            emptyArtwork
        }
    }

    private var resolvedThumbnail: UIImage? {
        guard let thumbnail, thumbnailURL == artworkURL || thumbnailURL == fallbackArtworkURL else {
            return nil
        }
        return thumbnail
    }

    /// A small logo shown at a size it can actually hold, over a wash of itself.
    ///
    /// Stretching a 128 px favicon across a 500 px tile is what made half the
    /// grid look out of focus — ImageIO never upscales on decode, so the blur
    /// was this view's doing. The backdrop is a blurred copy of the same image
    /// rather than a generated colour: it is guaranteed to harmonise, because it
    /// *is* the artwork. A generated hue here put magenta behind one KEXP logo
    /// and green behind the other, which looked arbitrary because it was.
    ///
    /// The neutral card fill underneath matters for the common case of a logo
    /// with a transparent background, where the blurred copy contributes almost
    /// nothing and the tile would otherwise be see-through.
    private func lowResolutionArtwork(_ image: UIImage) -> some View {
        ZStack {
            Color.shoutKitCardBackground

            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .blur(radius: 24, opaque: false)
                .opacity(0.55)

            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(insetPadding)
                .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
        }
    }

    /// No artwork at all — the only place a generated identity belongs, since
    /// there is nothing for it to clash with.
    @ViewBuilder
    private var emptyArtwork: some View {
        if let placeholderSeed {
            ArtworkPlaceholder(seed: placeholderSeed)
        } else {
            shape
                .fill(.tint.opacity(0.16))
                .overlay {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: sizing.decodeSize * 0.34))
                        .foregroundStyle(.tint)
                }
        }
    }

    /// `UIImage(cgImage:)` carries scale 1, so `size` is the decoded pixel count
    /// — directly comparable with the pixels this tile asked for.
    private func isLowResolution(_ image: UIImage) -> Bool {
        let wanted = sizing.decodeSize * displayScale
        guard wanted > 0 else { return false }
        return max(image.size.width, image.size.height) < wanted * Self.lowResolutionFraction
    }

    private var insetPadding: CGFloat {
        switch sizing {
        case .fixed(let size): size * 0.16
        case .flexible: ShoutKitSpacing.large
        }
    }

    @ViewBuilder
    private var playingLayer: some View {
        if isPlaying {
            ZStack {
                shape.fill(.black.opacity(0.35))
                PlayingIndicator(color: .white, isAnimating: true)
            }
        }
    }

    private func loadArtwork() async {
        let loaded = await ArtworkLoadPolicy.loadWithSource(artworkRequest) { url in
            await ArtworkThumbnailLoader.thumbnail(
                for: url,
                maxPixelSize: sizing.decodeSize * displayScale
            )
        }
        // A task cancelled by a URL change can still resume here with a stale
        // (or nil, from a cancelled fetch) result — don't let it clobber the
        // replacement task's image.
        guard Task.isCancelled == false else { return }
        thumbnail = loaded?.artwork
        thumbnailURL = loaded?.sourceURL
    }

    private var artworkRequest: ArtworkLoadRequest {
        ArtworkLoadRequest(primaryURL: artworkURL, fallbackURL: fallbackArtworkURL)
    }
}

/// Applies the square geometry for either sizing. Split out because the two
/// branches return different concrete types and can't be inlined into `body`
/// without erasing them.
private struct SquareSizing: ViewModifier {
    let sizing: StationArtworkView.Sizing

    func body(content: Content) -> some View {
        switch sizing {
        case let .fixed(size):
            content.frame(width: size, height: size)
        case .flexible:
            content
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    VStack {
        HStack {
            StationArtworkView(artworkURL: nil)
            StationArtworkView(artworkURL: nil, isPlaying: true)
        }
        LazyVGrid(columns: ShoutKitLayout.artworkColumns, spacing: ShoutKitSpacing.medium) {
            StationArtworkView.filling(artworkURL: nil)
            StationArtworkView.filling(artworkURL: nil, isPlaying: true)
        }
    }
    .padding()
    .tint(.shoutKitAccent)
}
