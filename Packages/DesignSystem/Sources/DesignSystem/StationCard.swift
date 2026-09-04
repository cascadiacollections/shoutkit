import Playback
import RadioDirectory
import SwiftUI

/// A poster-style station tile: square artwork over a name and one line of
/// metadata.
///
/// Two widths. **Fixed** for a horizontal carousel, where the card's width is
/// what makes the next card peek in from the trailing edge. **Flexible** — the
/// default for ``ShoutKitLayout/artworkColumns`` — where the grid decides the
/// width and the tile fills it.
///
/// Presentational only; state and callbacks come from the feature layer, same
/// contract as ``StationRow``.
public struct StationCard: View {
    private static let removeFavoriteTitle = String(localized: "Remove Favorite", bundle: .module)
    private static let addFavoriteTitle = String(localized: "Add to Favorites", bundle: .module)
    private static let pausesPlaybackHint = String(localized: "Pauses playback", bundle: .module)
    private static let playsStationHint = String(localized: "Plays this station", bundle: .module)

    private let station: Station
    private let phase: StationPlaybackPhase
    private let isFavorite: Bool
    private let onTap: () -> Void
    private let onToggleFavorite: (() -> Void)?
    private let removeAction: StationRowAction?
    /// `nil` fills the container; a value pins the tile to that width.
    @ScaledMetric(relativeTo: .headline) private var fixedWidth: CGFloat = 150
    private let hasFixedWidth: Bool

    /// A tile that fills the width its container gives it — the poster grid.
    public init(
        station: Station,
        phase: StationPlaybackPhase,
        isFavorite: Bool = false,
        onTap: @escaping () -> Void,
        onToggleFavorite: (() -> Void)? = nil,
        removeAction: StationRowAction? = nil
    ) {
        self.station = station
        self.phase = phase
        self.isFavorite = isFavorite
        self.onTap = onTap
        self.onToggleFavorite = onToggleFavorite
        self.removeAction = removeAction
        hasFixedWidth = false
    }

    /// A tile pinned to `width`, for horizontal carousels.
    public init(
        station: Station,
        phase: StationPlaybackPhase,
        width: CGFloat,
        isFavorite: Bool = false,
        onTap: @escaping () -> Void,
        onToggleFavorite: (() -> Void)? = nil,
        removeAction: StationRowAction? = nil
    ) {
        self.station = station
        self.phase = phase
        self.isFavorite = isFavorite
        self.onTap = onTap
        self.onToggleFavorite = onToggleFavorite
        self.removeAction = removeAction
        _fixedWidth = ScaledMetric(wrappedValue: width, relativeTo: .headline)
        hasFixedWidth = true
    }

    private var isActive: Bool {
        phase == .playing || phase == .paused || phase == .loading
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: ShoutKitSpacing.small) {
                artwork
                caption
            }
            .frame(width: hasFixedWidth ? fixedWidth : nil, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(phase == .playing ? Self.pausesPlaybackHint : Self.playsStationHint)
        .accessibilityAddTraits(.isButton)
        // The context menu is invisible to VoiceOver, so expose the same action
        // as a custom action too — same pairing as `StationRow`.
        .accessibilityActions {
            if onToggleFavorite != nil {
                Button(isFavorite ? Self.removeFavoriteTitle : Self.addFavoriteTitle) {
                    onToggleFavorite?()
                }
            }
            if let removeAction {
                Button(removeAction.title, action: removeAction.perform)
            }
        }
        .contextMenu {
            if let onToggleFavorite {
                Button {
                    onToggleFavorite()
                } label: {
                    Label(isFavorite ? Self.removeFavoriteTitle : Self.addFavoriteTitle,
                          systemImage: isFavorite ? "heart.slash" : "heart")
                }
            }
            if let removeAction {
                Button(role: .destructive, action: removeAction.perform) {
                    Label(removeAction.title, systemImage: removeAction.systemImage)
                }
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        let art = artworkView
        art.overlay(alignment: .topTrailing) { favoriteBadge }
    }

    @ViewBuilder
    private var artworkView: some View {
        if hasFixedWidth {
            StationArtworkView(
                artworkURL: station.artworkURL,
                size: fixedWidth,
                cornerRadius: ShoutKitRadius.card,
                isPlaying: phase == .playing,
                placeholderSeed: station.name
            )
        } else {
            StationArtworkView.filling(
                artworkURL: station.artworkURL,
                cornerRadius: ShoutKitRadius.card,
                isPlaying: phase == .playing,
                placeholderSeed: station.name
            )
        }
    }

    /// A favorited tile says so on the artwork itself. Rows carried this in a
    /// trailing accessory they had room for; a poster tile's only text is the
    /// name and one metadata line, and neither should be spent on it.
    @ViewBuilder
    private var favoriteBadge: some View {
        if isFavorite {
            Image(systemName: "heart.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                .padding(ShoutKitSpacing.small)
                // Decorative: "favorite" is already in the tile's label, and a
                // second announcement of it here would just be a repeat.
                .accessibilityHidden(true)
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(station.name)
                .font(.shoutKitCardTitle)
                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .lineLimit(1)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Genre, or the listener count when there is one.
    ///
    /// Bitrate used to appear here whenever a station reported no listeners,
    /// which meant a grid of tiles captioned "Eclectic / Indie · 160 kbps".
    /// A poster caption has room for one fact, and for choosing what to play
    /// that fact is not the encoder setting.
    private var subtitle: String {
        if station.listenerCount > 0 {
            return "\(station.listenerCount.formatted()) listeners"
        }
        return station.genre
    }

    private var accessibilityLabel: String {
        "\(station.name), \(subtitle)" + (isFavorite ? ", favorite" : "")
    }
}

#Preview {
    ScrollView {
        LazyVGrid(columns: ShoutKitLayout.artworkColumns, spacing: ShoutKitSpacing.large) {
            ForEach(PreviewRadioDirectory.sampleStations) { station in
                StationCard(
                    station: station,
                    phase: station.id == PreviewRadioDirectory.sampleStations.first?.id ? .playing : .idle,
                    isFavorite: station.id == PreviewRadioDirectory.sampleStations.last?.id,
                    onTap: {},
                    onToggleFavorite: {}
                )
            }
        }
        .padding()
    }
    .tint(.shoutKitAccent)
}
