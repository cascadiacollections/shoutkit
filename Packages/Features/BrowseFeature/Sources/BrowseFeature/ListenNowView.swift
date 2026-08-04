import BrowseFeatureCore
import DesignSystem
import FeatureFlags
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
    private enum Configuration {
        static let recommendationLimit = 10
        /// How many of the top stations become poster cards. The rest fall
        /// through to the list below, so nothing appears in both.
        static let carouselLimit = 10
    }

    @State private var viewModel: BrowseViewModel
    @Environment(\.playbackController) private var playback
    @Environment(\.libraryStore) private var library
    @Environment(\.displayScale) private var displayScale
    private let recommendationService: any RecommendationServicing
    private let featureFlags: any FeatureFlagProviding
    @State private var cachedRecommendations: [Station] = []
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
        viewModel: @autoclosure @escaping () -> BrowseViewModel = BrowseViewModel(),
        recommendationService: (any RecommendationServicing)? = nil,
        featureFlags: (any FeatureFlagProviding)? = nil
    ) {
        _viewModel = State(wrappedValue: viewModel())
        self.recommendationService = recommendationService ?? sharedRecommendationService()
        self.featureFlags = featureFlags ?? sharedFeatureFlags()
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
    // `recents` for recommendation scoring (see `LibraryStore.hideFromListenNow`).
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
                "Nothing here yet",
                systemImage: "dot.radiowaves.left.and.right",
                description: Text("Pull to refresh or try again soon.")
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

            recommendationsSection(loaded)

            popularCarousel(loaded)

            moreStations(loaded)
        }
    }

    private var loadingState: some View {
        VStack(spacing: ShoutKitSpacing.medium) {
            ProgressView()
            Text("Tuning in…")
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
        // A soft hide, not `removeRecent` — the play record stays intact so
        // recommendations still learn from it even once this teaser is empty.
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

    @ViewBuilder
    private func recommendationsSection(_ loaded: BrowseContent) -> some View {
        // Result builders don't support `guard`, so gate with `if`. The
        // `.task` sits on the (possibly empty) Group so recommendations still
        // compute before the first carousel render.
        if recommendationsEnabled {
            VStack(alignment: .leading, spacing: ShoutKitSpacing.small) {
                SectionHeaderView(String(localized: "More Like This", bundle: .module))
                if cachedRecommendations.isEmpty {
                    // Otherwise the flag has no visible effect at all, and
                    // looks like it silently did nothing after being enabled.
                    Text(String(localized: "Play a few stations to get recommendations here.", bundle: .module))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    StationCarousel(
                        stations: cachedRecommendations,
                        phase: { playback?.phase(for: $0) ?? .idle },
                        onTap: { playback?.toggle($0) }
                    )
                }
            }
            .task(id: recommendationCacheKey(loaded)) {
                cachedRecommendations = recommendationService.moreLikeThis(
                    from: recents.map(\.station),
                    candidates: loaded.stations,
                    limit: Configuration.recommendationLimit
                ).map(\.station)
            }
        }
    }

    private var recommendationsEnabled: Bool {
        featureFlags.isEnabled(FeatureCatalog.recommendations)
    }

    private func recommendationCacheKey(_ loaded: BrowseContent) -> UInt64 {
        // Bounded inputs: recents cap at 25 and browse stations at 24.
        RecommendationHashing.stableHash(segments: recents.map(\.stationID) + loaded.stations.map(\.id))
    }

    private func popularCarousel(_ loaded: BrowseContent) -> some View {
        VStack(alignment: .leading, spacing: ShoutKitSpacing.small) {
            SectionHeaderView(String(localized: "Popular Stations", bundle: .module))
            StationCarousel(
                stations: Array(loaded.stations.prefix(Configuration.carouselLimit)),
                phase: { playback?.phase(for: $0) ?? .idle },
                onTap: { playback?.toggle($0) }
            )
        }
    }

    /// The tail of the popular list, as rows. The carousel above already showed
    /// the head of it, so this section starts where that one stopped.
    @ViewBuilder
    private func moreStations(_ loaded: BrowseContent) -> some View {
        let stations = Array(loaded.stations.dropFirst(Configuration.carouselLimit))
        if stations.isEmpty == false {
            VStack(alignment: .leading, spacing: ShoutKitSpacing.small) {
                SectionHeaderView(String(localized: "More Stations", bundle: .module))
                LazyVGrid(columns: ShoutKitLayout.stationColumns, spacing: ShoutKitSpacing.small) {
                    ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                        StationRow(
                            station: station,
                            phase: playback?.phase(for: station) ?? .idle,
                            isFavorite: library?.isFavorite(station) ?? false,
                            onTap: { playback?.toggle(station) },
                            onToggleFavorite: library.map { store in { store.toggleFavorite(station) } }
                        )
                        .prefetchStationArtwork(after: index, in: stations, displayScale: displayScale)
                    }
                }
            }
        }
    }
}
