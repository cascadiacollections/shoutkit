import BrowseFeatureCore
import DesignSystem
import Persistence
import Playback
import RadioDirectory
import SwiftData
import SwiftUI

/// The home surface: what you just played, what that suggests, and what's
/// popular right now — personal content first, the directory underneath.
///
/// This is the app's only discovery screen. It used to share the job with a
/// Browse tab that showed the *same* `topStations` fetch as a carousel and then
/// again as a grid, one tap away; the two are one surface now, and the popular
/// carousel and the station list below it are disjoint slices of the same list
/// rather than the same ten stations twice.
public struct ListenNowView: View {
    @State private var viewModel: BrowseViewModel
    @Environment(\.playbackController) private var playback
    @Environment(\.libraryStore) private var library
    @Environment(\.displayScale) private var displayScale
    // See `RecentlyPlayedTeaserState` (Persistence) for the no-backfill dismiss logic.
    @State private var recentlyPlayedTeaser = RecentlyPlayedTeaserState()
    @State private var dismissUndo: DismissUndo?
    @State private var dismissUndoExpiryTask: Task<Void, Never>?

    private struct DismissUndo {
        let stationID: String
        let stationName: String
        let restoreIndex: Int
    }

    @Query(sort: \RecentStation.playedAt, order: .reverse)
    private var recents: [RecentStation]

    public init(
        viewModel: @autoclosure @escaping () -> BrowseViewModel = BrowseViewModel()
    ) {
        _viewModel = State(wrappedValue: viewModel())
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ShoutKitSpacing.large) {
                content
            }
            .padding(.horizontal, ShoutKitSpacing.medium)
            .padding(.vertical, ShoutKitSpacing.medium)
        }
        .background(Color.shoutKitBackground)
        // Content dissolves under the toolbar's glass rather than colliding
        // with a hard edge. `.soft` because what scrolls under this bar is
        // full-bleed artwork, which a hard cut slices visibly.
        .scrollEdgeEffectStyle(.soft, for: .top)
        .task { await viewModel.refresh() }
        .refreshable { await viewModel.refresh(source: .userInitiated) }
        .onChange(of: recents.map(\.stationID), initial: true) { _, _ in
            recentlyPlayedTeaser.sync(withVisibleIDsNewestFirst: visibleRecents.map(\.stationID))
        }
        // A safe-area inset rather than an overlay: as an overlay the banner
        // rendered *under* the tab bar's mini-player accessory, which is exactly
        // where the bottom of this screen already is.
        .safeAreaInset(edge: .bottom) { dismissUndoBanner }
        .animation(.default, value: dismissUndo?.stationID)
    }

    /// The banner is glass, so it should form rather than arrive.
    ///
    /// It used to slide up from the bottom edge and cross-fade, which is a
    /// transition for an opaque panel: the capsule travelled across the screen
    /// as a half-transparent rectangle before settling. `.materialize` inside a
    /// `GlassEffectContainer` is the glass-native equivalent — it condenses into
    /// its capsule in place, which is what the system's own transient glass
    /// (the volume HUD, the AirPods banner) does.
    ///
    /// Under Reduce Transparency `GlassControlSurface` renders an opaque
    /// material instead of glass, and the transition is inert there — which is
    /// the correct outcome, not a gap: that setting exists to stop exactly this
    /// kind of motion-plus-translucency.
    @ViewBuilder
    private var dismissUndoBanner: some View {
        if let dismissUndo {
            GlassEffectContainer(spacing: 0) {
                GlassControlSurface(in: Capsule()) {
                    HStack(spacing: ShoutKitSpacing.small) {
                        Text(String(localized: "\(dismissUndo.stationName) removed", bundle: .module))
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: ShoutKitSpacing.small)
                        Button(String(localized: "Undo", bundle: .module)) {
                            undoDismiss(dismissUndo)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, ShoutKitSpacing.small)
                }
                .glassEffectTransition(.materialize)
            }
            .padding(.horizontal, ShoutKitSpacing.medium)
            .padding(.bottom, ShoutKitSpacing.small)
        }
    }

    // Recents dismissed from the Listen Now teaser but still present in
    // `recents`, which remains the play record the Library's own list and the
    // station ranking read (see `LibraryStore.hideFromListenNow`).
    private var visibleRecents: [RecentStation] {
        recents.filter { $0.isHiddenFromListenNow == false }
    }

    private var displayedRecentStations: [RecentStation] {
        let byID = Dictionary(uniqueKeysWithValues: recents.map { ($0.stationID, $0) })
        return recentlyPlayedTeaser.displayedIDs.compactMap { byID[$0] }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            loadingState
        case .empty:
            ContentUnavailableView(
                String(localized: "Nothing here yet", bundle: .module),
                systemImage: "dot.radiowaves.left.and.right",
                description: Text(String(localized: "Pull to refresh or try again soon.", bundle: .module))
            )
            .frame(maxWidth: .infinity, minHeight: 260)
        case let .failed(error):
            DirectoryUnavailableView(
                title: String(localized: "Directory Unavailable", bundle: .module),
                error: error,
                minHeight: 260
            ) {
                Task { await viewModel.refresh(source: .userInitiated) }
            }
        case let .loaded(loaded):
            SavedStationsNotice(origin: loaded.origin, refreshError: viewModel.refreshError)

            recentlyPlayed

            popularStations(loaded)
        }
    }

    private var loadingState: some View {
        VStack(spacing: ShoutKitSpacing.medium) {
            ProgressView()
            Text(String(localized: "Tuning in…", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    @ViewBuilder
    private var recentlyPlayed: some View {
        let displayed = displayedRecentStations
        if displayed.isEmpty == false {
            VStack(alignment: .leading, spacing: ShoutKitSpacing.small) {
                SectionHeaderView(String(localized: "Recently Played", bundle: .module))
                // A shelf of the same poster tiles the grid below uses, not
                // full-width rows. Rows put a solid card floating above a
                // card-less grid — the one place on this screen where two
                // visual languages met. Distinguishing a short personal list
                // from a long popular one by axis reads as intended; doing it
                // by component read as unfinished.
                //
                // Dismissal stays in the tile's context menu (and as a
                // VoiceOver action), which is where iOS puts "remove this
                // suggestion" and where the row had already moved it.
                StationCarousel(
                    stations: displayed.map(\.station),
                    phase: { playback?.phase(for: $0) ?? .idle },
                    isFavorite: { library?.isFavorite($0) ?? false },
                    onTap: { playback?.toggle($0) },
                    onToggleFavorite: library.map { store in { store.toggleFavorite($0) } },
                    removeAction: { station in
                        StationRowAction(
                            title: String(localized: "Remove from Recently Played", bundle: .module),
                            systemImage: "clock.badge.xmark"
                        ) {
                            dismissRecent(station: station, in: displayed)
                        }
                    }
                )
            }
        }
    }

    /// Resolves the station back to its position in the displayed shelf, so an
    /// undo can put it back where it was rather than at the front.
    private func dismissRecent(station: Station, in displayed: [RecentStation]) {
        guard let index = displayed.firstIndex(where: { $0.stationID == station.id }) else { return }
        dismissRecent(
            stationID: station.id,
            stationName: displayed[index].name,
            at: index
        )
    }

    private func dismissRecent(stationID: String, stationName: String, at index: Int) {
        // A soft hide, not `removeRecent` — dismissing a card from this teaser
        // is not "forget I played this". The play record stays intact for the
        // Library's Recently Played list and for `rankedStations`, which feeds
        // CarPlay and the quick-play widget.
        library?.hideFromListenNow(stationID: stationID)
        // Removed here too (not just left to the query refresh) so the slot
        // doesn't backfill from `recents` — dismissing shrinks the list.
        recentlyPlayedTeaser.remove(stationID)
        presentDismissUndo(stationID: stationID, stationName: stationName, restoreIndex: index)
    }

    private func presentDismissUndo(stationID: String, stationName: String, restoreIndex: Int) {
        dismissUndo = DismissUndo(stationID: stationID, stationName: stationName, restoreIndex: restoreIndex)
        // Cancel-and-replace rather than matching on stationID at expiry: a
        // dismiss → undo → re-dismiss of the *same* station within the window
        // would otherwise let the stale timer clear the fresh banner early.
        dismissUndoExpiryTask?.cancel()
        dismissUndoExpiryTask = Task {
            guard (try? await Task.sleep(for: .seconds(4))) != nil else { return }
            dismissUndo = nil
        }
    }

    private func undoDismiss(_ undo: DismissUndo) {
        library?.unhideFromListenNow(stationID: undo.stationID)
        recentlyPlayedTeaser.restore(undo.stationID, at: undo.restoreIndex)
        dismissUndoExpiryTask?.cancel()
        dismissUndo = nil
    }

    /// Every popular station, as one poster grid.
    ///
    /// This was a ten-card carousel above a list of rows holding the *rest* of
    /// the same fetch — disjoint slices, so nothing appeared twice, but two
    /// different shapes for one list. The split asked the reader to understand
    /// that the horizontal strip and the vertical list were the same kind of
    /// thing, and it capped the artwork on the larger half at a 56 pt row
    /// thumbnail. One grid says it once, and gives every station the same
    /// poster the top ten used to get to themselves.
    private func popularStations(_ loaded: BrowseContent) -> some View {
        VStack(alignment: .leading, spacing: ShoutKitSpacing.small) {
            // A section header separates sections. When Recently Played is
            // absent — every fresh install — this is the only one, so the
            // header labels the whole screen directly under a title that
            // already did, and costs a bold line before any station.
            if displayedRecentStations.isEmpty == false {
                SectionHeaderView(String(localized: "Popular Stations", bundle: .module))
            }
            LazyVGrid(columns: ShoutKitLayout.artworkColumns, spacing: ShoutKitSpacing.large) {
                ForEach(Array(loaded.stations.enumerated()), id: \.element.id) { index, station in
                    StationCard(
                        station: station,
                        phase: playback?.phase(for: station) ?? .idle,
                        isFavorite: library?.isFavorite(station) ?? false,
                        onTap: { playback?.toggle(station) },
                        onToggleFavorite: library.map { store in { store.toggleFavorite(station) } }
                    )
                    .prefetchStationArtwork(
                        after: index,
                        in: loaded.stations,
                        displayScale: displayScale,
                        // Tiles decode at poster size; prefetching at row size
                        // would warm a cache entry the tile never reads.
                        maxPixelSize: StationArtworkView.posterPixelSize(displayScale: displayScale)
                    )
                }
            }
        }
    }
}
