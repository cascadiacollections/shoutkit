import DesignSystem
import FeatureFlags
import Persistence
import Playback
import RadioDirectory
import SwiftData
import SwiftUI

/// A lighter, personalized landing: a featured spotlight, recently played, and a
/// popular carousel. Reuses ``BrowseViewModel`` for directory content.
public struct ListenNowView: View {
    private enum Configuration {
        static let recommendationLimit = 10
    }

    @State private var viewModel: BrowseViewModel
    @Environment(\.playbackController) private var playback
    @Environment(\.libraryStore) private var library
    private let recommendationService: any RecommendationServicing
    private let featureFlags: any FeatureFlagProviding
    @State private var cachedRecommendations: [Station] = []
    // See `RecentlyPlayedTeaserState` (Persistence) for the no-backfill dismiss logic.
    @State private var recentlyPlayedTeaser = RecentlyPlayedTeaserState()

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
        .refreshable { await viewModel.refresh() }
        .onChange(of: recents.map(\.stationID), initial: true) { _, _ in
            recentlyPlayedTeaser.sync(withVisibleIDsNewestFirst: visibleRecents.map(\.stationID))
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
            ProgressView("Tuning in…")
                .frame(maxWidth: .infinity, minHeight: 260)
        case .empty:
            ContentUnavailableView("Nothing here yet", systemImage: "radio")
                .frame(maxWidth: .infinity, minHeight: 260)
        case let .failed(error):
            ContentUnavailableView {
                Label("Directory Unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                if error.isRetryable {
                    Button("Try Again") {
                        Task { await viewModel.refresh() }
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 260)
        case let .loaded(loaded):
            if BrowseConfiguration.showsFeaturedSpotlight, let spotlight = loaded.spotlight {
                SpotlightCard(
                    station: spotlight,
                    phase: playback?.phase(for: spotlight) ?? .idle,
                    onPlay: { playback?.toggle(spotlight) }
                )
            }

            recentlyPlayed

            recommendationsSection(loaded)

            popularCarousel(loaded)
        }
    }

    @ViewBuilder
    private var recentlyPlayed: some View {
        let displayed = displayedRecentStations
        if displayed.isEmpty == false {
            VStack(alignment: .leading, spacing: ShoutKitSpacing.small) {
                SectionHeaderView(String(localized: "Recently Played", bundle: .module))
                // A real List (rather than the LazyVGrid used elsewhere on this screen) is
                // required for swipe-to-dismiss; it's nested inside the outer ScrollView
                // with its own scrolling disabled and sized to its content.
                List {
                    ForEach(displayed) { recent in
                        let station = recent.station
                        StationRow(
                            station: station,
                            phase: playback?.phase(for: station) ?? .idle,
                            isFavorite: library?.isFavorite(station) ?? false,
                            onTap: { playback?.toggle(station) },
                            onToggleFavorite: library.map { store in { store.toggleFavorite(station) } }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: deleteRecents)
                }
                .listStyle(.plain)
                .listRowSpacing(ShoutKitSpacing.small)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                .frame(height: recentlyPlayedListHeight(count: displayed.count))
            }
        }
    }

    private func recentlyPlayedListHeight(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let rowHeight: CGFloat = 76
        return CGFloat(count) * rowHeight + CGFloat(count - 1) * ShoutKitSpacing.small
    }

    private func deleteRecents(at offsets: IndexSet) {
        // Materialise the displayed slice before removal so offset resolution
        // isn't affected by live-query updates mid-deletion (same approach as
        // LibraryView's deleteRecents).
        let displayed = displayedRecentStations
        let stationIDs = offsets.map { displayed[$0].stationID }
        for stationID in stationIDs {
            // A soft hide, not `removeRecent` — the play record stays intact so
            // recommendations still learn from it even once this teaser is empty.
            library?.hideFromListenNow(stationID: stationID)
            // Removed here too (not just left to the query refresh) so the slot
            // doesn't backfill from `recents` — dismissing shrinks the list.
            recentlyPlayedTeaser.remove(stationID)
        }
    }

    @ViewBuilder
    private func recommendationsSection(_ loaded: BrowseContent) -> some View {
        // Result builders don't support `guard`, so gate with `if`. The
        // `.task` sits on the (possibly empty) Group so recommendations still
        // compute before the first carousel render.
        if recommendationsEnabled {
            Group {
                if !cachedRecommendations.isEmpty {
                    VStack(alignment: .leading, spacing: ShoutKitSpacing.small) {
                        SectionHeaderView(String(localized: "More Like This", bundle: .module))
                        StationCarousel(
                            stations: cachedRecommendations,
                            phase: { playback?.phase(for: $0) ?? .idle },
                            onTap: { playback?.toggle($0) }
                        )
                    }
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
                stations: Array(loaded.stations.prefix(10)),
                phase: { playback?.phase(for: $0) ?? .idle },
                onTap: { playback?.toggle($0) }
            )
        }
    }
}
