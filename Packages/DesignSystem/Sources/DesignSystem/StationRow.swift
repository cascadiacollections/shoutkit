import Playback
import RadioDirectory
import SwiftUI

/// A reusable station list row: artwork, name, metadata, and a glass play/pause
/// indicator that reflects the shared playback phase. Presentational only — state
/// and callbacks are injected by the feature layer.
///
/// The whole row is a single `Button` rather than a tap-gesture surface wrapping a
/// second, separate `Button` — nesting a button inside a tappable region produces
/// ambiguous hit-testing and collapses to one confusing VoiceOver element.
public struct StationRow: View {
    private let station: Station
    private let phase: StationPlaybackPhase
    private let isFavorite: Bool
    private let onTap: () -> Void
    private let onToggleFavorite: (() -> Void)?

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(
        station: Station,
        phase: StationPlaybackPhase,
        isFavorite: Bool = false,
        onTap: @escaping () -> Void,
        onToggleFavorite: (() -> Void)? = nil
    ) {
        self.station = station
        self.phase = phase
        self.isFavorite = isFavorite
        self.onTap = onTap
        self.onToggleFavorite = onToggleFavorite
    }

    private var isActive: Bool {
        phase == .playing || phase == .paused || phase == .loading
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: ShoutKitSpacing.medium) {
                StationArtworkView(artworkURL: station.artworkURL, isPlaying: phase == .playing)

                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: ShoutKitSpacing.small)

                playIndicator
            }
            .padding(ShoutKitSpacing.small)
            .background {
                RoundedRectangle(cornerRadius: ShoutKitRadius.medium, style: .continuous)
                    .fill(isActive ? AnyShapeStyle(.tint.opacity(0.10)) : AnyShapeStyle(.background))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(phase == .playing ? "Pauses playback" : "Plays this station")
        // The context menu is invisible to VoiceOver, so expose the favorite
        // toggle as a custom action too.
        .accessibilityActions {
            if onToggleFavorite != nil {
                Button(isFavorite ? "Remove Favorite" : "Add to Favorites") {
                    onToggleFavorite?()
                }
            }
        }
        .contextMenu {
            if let onToggleFavorite {
                Button {
                    onToggleFavorite()
                } label: {
                    Label(isFavorite ? "Remove Favorite" : "Add to Favorites",
                          systemImage: isFavorite ? "heart.slash" : "heart")
                }
            }
        }
    }

    /// A visual play/pause indicator only — not its own tappable control. The
    /// whole row is the button; this just renders the circular glass affordance,
    /// falling back to material + stroke under Reduce Transparency/Increase
    /// Contrast exactly like `GlassControlSurface`.
    @ViewBuilder
    private var playIndicator: some View {
        let icon = Group {
            switch phase {
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case .playing:
                Image(systemName: "pause.fill")
            case .idle, .paused, .failed:
                Image(systemName: "play.fill")
            }
        }
        .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))

        if reduceTransparency || colorSchemeContrast == .increased {
            icon
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .overlay { Circle().stroke(.primary.opacity(0.18), lineWidth: 1) }
        } else {
            icon
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: Circle())
        }
    }

    private var subtitle: String {
        if station.listenerCount > 0 {
            return "\(station.genre) · \(station.listenerCount.formatted()) listeners"
        }
        if let bitrate = station.bitrate {
            return "\(station.genre) · \(bitrate) kbps"
        }
        return station.genre
    }

    private var accessibilityLabel: String {
        "\(station.name), \(subtitle)" + (isFavorite ? ", favorite" : "")
    }
}

#Preview {
    VStack {
        StationRow(
            station: PreviewRadioDirectory.sampleStations[0],
            phase: .playing,
            isFavorite: true,
            onTap: {},
            onToggleFavorite: {}
        )
        StationRow(
            station: PreviewRadioDirectory.sampleStations[2],
            phase: .idle,
            onTap: {}
        )
    }
    .padding()
    .tint(.shoutKitAccent)
}
