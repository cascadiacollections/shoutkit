import BrowseFeatureCore
import DesignSystem
import Persistence
import Playback
import RadioDirectory
import SwiftUI

/// The popular-stations grid, replaced by one genre.
///
/// `BrowseViewModel.toggleGenreFilter` already fetched this list into
/// `genrePhase`. Listen Now never read it, so a welcome chip would have loaded
/// stations the screen did not show. Recently Played stays with the parent:
/// this is only the directory section. All Stations clears the filter and the
/// popular grid returns.
struct ListenNowGenreSection: View {
    let genre: String
    let phase: GenreStationsPhase?
    let onShowAll: () -> Void
    let onRetry: () -> Void

    @Environment(\.playbackController) private var playback
    @Environment(\.libraryStore) private var library
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: ShoutKitSpacing.small) {
            header
            stations
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: genre)
                .font(.shoutKitSectionTitle)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button(String(localized: "All Stations", bundle: .module), action: onShowAll)
                .font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder
    private var stations: some View {
        if let phase {
            loadedOrFailed(phase)
        } else {
            loading
        }
    }

    @ViewBuilder
    private func loadedOrFailed(_ phase: GenreStationsPhase) -> some View {
        switch phase {
        case .loading:
            loading
        case let .failed(error):
            DirectoryUnavailableView(
                title: String(localized: "Directory Unavailable", bundle: .module),
                error: error,
                minHeight: 200,
                retry: onRetry,
            )
        case let .loaded(stations):
            if stations.isEmpty {
                ContentUnavailableView(
                    String(localized: "Nothing in this genre right now", bundle: .module),
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text(
                        String(localized: "Show all stations to see what's popular.", bundle: .module),
                    ),
                )
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                grid(stations)
            }
        }
    }

    private var loading: some View {
        VStack(spacing: ShoutKitSpacing.medium) {
            ProgressView()
            Text(String(localized: "Tuning in…", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func grid(_ stations: [Station]) -> some View {
        LazyVGrid(columns: ShoutKitLayout.artworkColumns, spacing: ShoutKitSpacing.large) {
            ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                StationCard(
                    station: station,
                    phase: playback?.phase(for: station) ?? .idle,
                    isFavorite: library?.isFavorite(station) ?? false,
                    onTap: { playback?.toggle(station) },
                    onToggleFavorite: library.map { store in { store.toggleFavorite(station) } },
                )
                .prefetchStationArtwork(
                    after: index,
                    in: stations,
                    displayScale: displayScale,
                    maxPixelSize: StationArtworkView.posterPixelSize(displayScale: displayScale),
                )
            }
        }
    }
}
