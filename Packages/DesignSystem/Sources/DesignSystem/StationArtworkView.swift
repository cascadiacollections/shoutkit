import RadioDirectory
import SwiftUI

/// Async-loading station artwork with a graceful glass placeholder and an optional
/// "now playing" overlay.
public struct StationArtworkView: View {
    private let artworkURL: URL?
    private let size: CGFloat
    private let cornerRadius: CGFloat
    private let isPlaying: Bool

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
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .empty, .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
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
