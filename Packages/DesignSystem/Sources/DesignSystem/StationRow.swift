import Playback
import RadioDirectory
import SwiftUI

/// An extra, destructive row action — offered in the row's context menu and as a
/// VoiceOver custom action. The title is supplied by the feature layer because
/// it's localized in that module's string catalog, not this one.
public struct StationRowAction {
    public let title: String
    public let systemImage: String
    public let perform: () -> Void

    public init(title: String, systemImage: String, perform: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.perform = perform
    }
}

/// A reusable station list row: artwork, name, metadata, and a glass play/pause
/// indicator that reflects the shared playback phase. Presentational only — state
/// and callbacks are injected by the feature layer.
///
/// The whole row is a single `Button` rather than a tap-gesture surface wrapping a
/// second, separate `Button` — nesting a button inside a tappable region produces
/// ambiguous hit-testing and collapses to one confusing VoiceOver element.
public struct StationRow: View {
    // `String(localized:bundle: .module)`, not bare literals: a `LocalizedStringKey`
    // built from a literal in a package resolves against `Bundle.main` — the *app's*
    // bundle — so the keys in this package's catalog are never consulted and the
    // strings ship untranslated. Same reasoning as DirectoryUnavailableView's
    // "Try Again". These four keys already existed in Localizable.xcstrings and were
    // dead entries until now.
    private static let pausesPlaybackHint = String(localized: "Pauses playback", bundle: .module)
    private static let playsStationHint = String(localized: "Plays this station", bundle: .module)
    private static let removeFavoriteTitle = String(localized: "Remove Favorite", bundle: .module)
    private static let addFavoriteTitle = String(localized: "Add to Favorites", bundle: .module)

    private let station: Station
    private let phase: StationPlaybackPhase
    private let isFavorite: Bool
    private let onTap: () -> Void
    private let onToggleFavorite: (() -> Void)?
    private let removeAction: StationRowAction?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
    }

    private var isActive: Bool {
        phase == .playing || phase == .paused || phase == .loading
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: ShoutKitSpacing.medium) {
                StationArtworkView(
                    artworkURL: station.artworkURL,
                    isPlaying: phase == .playing,
                    placeholderSeed: station.name,
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(nameLineLimit)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(subtitleLineLimit)
                }
                // Claim the wrapped height rather than whatever the row is
                // proposed, so the line limits above are what decides. The same
                // guard `StationCard`'s caption needed in a grid cell, where
                // without it the text truncated at one line whatever its limit.
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: ShoutKitSpacing.small)

                playIndicator
            }
            .padding(ShoutKitSpacing.small)
            .background {
                RoundedRectangle(cornerRadius: ShoutKitRadius.medium, style: .continuous)
                    .fill(isActive ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(Color.shoutKitCardBackground))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(phase == .playing ? Self.pausesPlaybackHint : Self.playsStationHint)
        // The context menu is invisible to VoiceOver, so expose the same actions
        // as custom actions too.
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
        // The shape the row lifts out of when the context menu opens. Without
        // it the system uses the view's bounds — a square-cornered rectangle
        // around a row whose background is a 16 pt continuous rounded
        // rectangle, so the corners squared off for the duration of the
        // long-press and the menu appeared to fly out of a different view than
        // the one under the finger. Same radius and style as the background
        // above, deliberately: the preview *is* that background.
        .contentShape(
            .contextMenuPreview,
            RoundedRectangle(cornerRadius: ShoutKitRadius.medium, style: .continuous),
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

    /// A visual play/pause indicator only — not its own tappable control. The
    /// whole row is the button; this just renders the circular glass affordance.
    private var playIndicator: some View {
        Group {
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
        .frame(width: 44, height: 44)
        .glassControlBackground(in: Circle())
    }

    /// One line at the standard sizes, where a row is a scannable list entry.
    /// At the accessibility sizes the text column between the 56 pt artwork and
    /// the 44 pt indicator is ~200 pt on a 375 pt-wide iPhone SE, which at
    /// `.headline` AX3 is a handful of glyphs — a station name cut to "KEX…"
    /// identifies nothing. Wrapping there is what the system lists do.
    private var nameLineLimit: Int {
        dynamicTypeSize.isAccessibilitySize ? 3 : 1
    }

    private var subtitleLineLimit: Int {
        dynamicTypeSize.isAccessibilitySize ? 2 : 1
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
            onToggleFavorite: {},
        )
        StationRow(
            station: PreviewRadioDirectory.sampleStations[2],
            phase: .idle,
            onTap: {},
        )
    }
    .padding()
    .tint(.shoutKitAccent)
}

#Preview("iPhone SE · AX3", traits: .iPhoneSE) {
    ScrollView {
        VStack {
            ForEach(PreviewRadioDirectory.sampleStations) { station in
                StationRow(
                    station: station,
                    phase: station.id == PreviewRadioDirectory.sampleStations.first?.id ? .playing : .idle,
                    onTap: {},
                )
            }
        }
        .padding()
    }
    .dynamicTypeSize(.narrowScreenPreview)
    .tint(.shoutKitAccent)
}
