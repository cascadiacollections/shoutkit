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
    @State private var viewModel: BrowseViewModel
    @Environment(\.playbackController) private var playback
    @Environment(\.libraryStore) private var library
    private let recommendationService: any RecommendationServicing
    private let featureFlags: any FeatureFlagProviding
    private let recommendationsFeature: Feature?
    @State private var cachedRecommendations: [Station] = []

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
        recommendationsFeature = FeatureCatalog.all.first(where: { $0.key == "recommendations" })
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
        if recents.isEmpty == false {
            VStack(alignment: .leading, spacing: ShoutKitSpacing.small) {
                SectionHeaderView(String(localized: "Recently Played", bundle: .module))
                LazyVGrid(columns: ShoutKitLayout.stationColumns, spacing: ShoutKitSpacing.small) {
                    ForEach(recents.prefix(5)) { recent in
                        let station = recent.station
                        StationRow(
                            station: station,
                            phase: playback?.phase(for: station) ?? .idle,
                            isFavorite: library?.isFavorite(station) ?? false,
                            onTap: { playback?.toggle(station) },
                            onToggleFavorite: library.map { store in { store.toggleFavorite(station) } }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recommendationsSection(_ loaded: BrowseContent) -> some View {
        guard recommendationsEnabled else { return }
        Group {
            if cachedRecommendations.isEmpty == false {
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
                limit: 10
            ).map(\.station)
        }
    }

    private var recommendationsEnabled: Bool {
        guard let recommendationsFeature else {
            return false
        }
        return featureFlags.isEnabled(recommendationsFeature)
    }

    private func recommendationCacheKey(_ loaded: BrowseContent) -> Int {
        var hasher = Hasher()
        recents.forEach { hasher.combine($0.stationID) }
        loaded.stations.forEach { hasher.combine($0.id) }
        return hasher.finalize()
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
