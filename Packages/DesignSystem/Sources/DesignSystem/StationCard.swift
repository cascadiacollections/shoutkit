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
    /// The unscaled width a fixed tile was asked for — the base of ``cardWidth``.
    private let baseFixedWidth: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// How far a fixed tile may grow with Dynamic Type, as a multiple of the
    /// width it was asked for.
    ///
    /// Unbounded, a 150 pt shelf tile scaled with `.headline` reaches ~350 pt at
    /// AX3 — more than the 343 pt between an iPhone SE's margins — and ~470 pt
    /// at AX5, wider than its whole screen. Either way the next tile no longer
    /// peeks in (the only cue the shelf scrolls) and the artwork decodes at a
    /// size nobody can see. 1.6× is roughly where scaling stops at the first
    /// accessibility size: 240 pt on the SE leaves the next tile visibly
    /// peeking past the 16 pt margins. The caption still grows; it wraps
    /// instead (see ``captionLineLimit``).
    private static let maximumFixedWidthScale: CGFloat = 1.6

    /// A tile that fills the width its container gives it — the poster grid.
    public init(
        station: Station,
        phase: StationPlaybackPhase,
        isFavorite: Bool = false,
        onTap: @escaping () -> Void,
        onToggleFavorite: (() -> Void)? = nil,
        removeAction: StationRowAction? = nil,
    ) {
        self.station = station
        self.phase = phase
        self.isFavorite = isFavorite
        self.onTap = onTap
        self.onToggleFavorite = onToggleFavorite
        self.removeAction = removeAction
        hasFixedWidth = false
        baseFixedWidth = 150
    }

    /// A tile pinned to `width`, for horizontal carousels.
    public init(
        station: Station,
        phase: StationPlaybackPhase,
        width: CGFloat,
        isFavorite: Bool = false,
        onTap: @escaping () -> Void,
        onToggleFavorite: (() -> Void)? = nil,
        removeAction: StationRowAction? = nil,
    ) {
        self.station = station
        self.phase = phase
        self.isFavorite = isFavorite
        self.onTap = onTap
        self.onToggleFavorite = onToggleFavorite
        self.removeAction = removeAction
        _fixedWidth = ScaledMetric(wrappedValue: width, relativeTo: .headline)
        hasFixedWidth = true
        baseFixedWidth = width
    }

    /// The fixed tile's width: scaled with Dynamic Type, capped at
    /// ``maximumFixedWidthScale``.
    private var cardWidth: CGFloat {
        min(fixedWidth, baseFixedWidth * Self.maximumFixedWidthScale)
    }

    /// One line per caption row at the standard sizes; at the accessibility
    /// sizes a name cut to its first few glyphs identifies nothing, so it wraps.
    private var captionLineLimit: Int {
        dynamicTypeSize.isAccessibilitySize ? 2 : 1
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
            .frame(width: hasFixedWidth ? cardWidth : nil, alignment: .leading)
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
        // The shape the tile lifts out of when the context menu opens. Left to
        // the system it is the view's bounds — square corners around a tile
        // whose artwork is a 20 pt continuous rounded rectangle, so a poster
        // grid squared itself off under the finger and the menu flew out of a
        // shape that wasn't on screen a moment earlier.
        //
        // Outset by a small step rather than tracing the bounds exactly: the
        // caption runs to the leading edge and sits inside the bottom 20 pt,
        // so a corner radius drawn *on* the bounds would cut the first glyph of
        // the subtitle. The outset also gives the lifted platter a margin, which
        // is what the system players' poster previews look like.
        .contentShape(
            .contextMenuPreview,
            RoundedRectangle(cornerRadius: ShoutKitRadius.card, style: .continuous)
                .inset(by: -ShoutKitSpacing.small),
        )
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
                size: cardWidth,
                cornerRadius: ShoutKitRadius.card,
                isPlaying: phase == .playing,
                placeholderSeed: station.name,
            )
        } else {
            StationArtworkView.filling(
                artworkURL: station.artworkURL,
                cornerRadius: ShoutKitRadius.card,
                isPlaying: phase == .playing,
                placeholderSeed: station.name,
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
                .lineLimit(captionLineLimit)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(captionLineLimit)
        }
        // Without this the line limit is never reached: in a grid cell the
        // aspect-fit artwork above is the flexible child, and the caption is
        // proposed only the height left over — one line — and truncates there
        // regardless of `lineLimit`. Seen on an iPhone SE simulator at AX3.
        .fixedSize(horizontal: false, vertical: true)
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
                    onToggleFavorite: {},
                )
            }
        }
        .padding()
    }
    .tint(.shoutKitAccent)
}

#Preview("iPhone SE · AX3", traits: .iPhoneSE) {
    ScrollView {
        LazyVGrid(columns: ShoutKitLayout.artworkColumns, spacing: ShoutKitSpacing.large) {
            ForEach(PreviewRadioDirectory.sampleStations) { station in
                StationCard(station: station, phase: .idle, onTap: {})
            }
        }
        .padding()
    }
    .dynamicTypeSize(.narrowScreenPreview)
    .tint(.shoutKitAccent)
}
