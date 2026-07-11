import DesignSystem
import Persistence
import Playback
import RadioDirectory
import SwiftUI

public struct BrowseLandingView: View {
    @State private var viewModel: BrowseViewModel
    @Environment(\.playbackController) private var playback
    @Environment(\.libraryStore) private var library

    public init(viewModel: @autoclosure @escaping () -> BrowseViewModel = BrowseViewModel()) {
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
        .task {
            await viewModel.refresh()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            loadingState
        case .empty:
            ContentUnavailableView(
                "No Stations",
                systemImage: "radio",
                description: Text("Pull to refresh or try again soon.")
            )
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
            loadedContent(loaded)
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
    private func loadedContent(_ loaded: BrowseContent) -> some View {
        if BrowseConfiguration.showsFeaturedSpotlight, let spotlight = loaded.spotlight {
            SpotlightCard(
                station: spotlight,
                phase: playback?.phase(for: spotlight) ?? .idle,
                onPlay: { playback?.toggle(spotlight) }
            )
        }

        if loaded.genres.isEmpty == false {
            genreFilter(loaded.genres)
        }

        popularCarousel(loaded)

        allStations(loaded)
    }

    private func genreFilter(_ genres: [Genre]) -> some View {
        VStack(alignment: .leading, spacing: ShoutKitSpacing.small) {
            SectionHeaderView(String(localized: "Genres", bundle: .module))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ShoutKitSpacing.small) {
                    ForEach(genres) { genre in
                        Button {
                            withAnimation(.snappy) { viewModel.toggleGenreFilter(genre.name) }
                        } label: {
                            Text(genre.name)
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.glass)
                        .tint(viewModel.selectedGenre == genre.name ? .shoutKitAccent : .primary)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
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

    @ViewBuilder
    private func allStations(_ loaded: BrowseContent) -> some View {
        VStack(alignment: .leading, spacing: ShoutKitSpacing.small) {
            SectionHeaderView(
                viewModel.selectedGenre.map { "\($0) Stations" } ?? "All Stations"
            )

            switch viewModel.genrePhase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            case let .failed(error):
                ContentUnavailableView(
                    "Couldn't Load Genre",
                    systemImage: "wifi.exclamationmark",
                    description: Text(error.localizedDescription)
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            case let .loaded(stations):
                if stations.isEmpty {
                    Text("No stations in this genre yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, ShoutKitSpacing.medium)
                } else {
                    stationRows(stations)
                }
            case nil:
                stationRows(loaded.stations)
            }
        }
    }

    private func stationRows(_ stations: [Station]) -> some View {
        LazyVGrid(columns: ShoutKitLayout.stationColumns, spacing: ShoutKitSpacing.small) {
            ForEach(stations) { station in
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

#Preview("Browse") {
    NavigationStack {
        BrowseLandingView()
            .navigationTitle("Browse")
    }
    .tint(.shoutKitAccent)
}
