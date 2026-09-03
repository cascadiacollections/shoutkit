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

    @ViewBuilder
    private var dismissUndoBanner: some View {
        if let dismissUndo {
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
            .padding(.horizontal, ShoutKitSpacing.medium)
            .padding(.bottom, ShoutKitSpacing.small)
            .transition(.move(edge: .bottom).combined(with: .opacity))
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
                // Plain rows, not a nested `List`. The `List` was here only to
                // get swipe-to-dismiss, and it had to be given an explicit
                // height computed from a hard-coded 76 pt row — a number that
                // stops being true at the first Dynamic Type step up, clipping
                // the last row or leaving a gap. Dismissal moved to the row's
                // context menu (and a VoiceOver action), which is where iOS puts
                // "remove this suggestion" anyway.
                ForEach(Array(displayed.enumerated()), id: \.element.stationID) { index, recent in
                    let station = recent.station
                    let stationID = recent.stationID
                    let stationName = recent.name
                    StationRow(
                        station: station,
                        phase: playback?.phase(for: station) ?? .idle,
                        isFavorite: library?.isFavorite(station) ?? false,
                        onTap: { playback?.toggle(station) },
                        onToggleFavorite: library.map { store in { store.toggleFavorite(station) } },
                        removeAction: StationRowAction(
                            title: String(localized: "Remove from Recently Played", bundle: .module),
                            systemImage: "clock.badge.xmark"
                        ) {
                            dismissRecent(stationID: stationID, stationName: stationName, at: index)
                        }
                    )
                }
            }
        }
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
            SectionHeaderView(String(localized: "Popular Stations", bundle: .module))
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
