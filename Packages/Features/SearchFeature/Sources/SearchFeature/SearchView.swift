import DesignSystem
import Persistence
import Playback
import RadioDirectory
import SwiftUI

public struct SearchView: View {
    @State private var viewModel: SearchViewModel
    @Environment(\.playbackController) private var playback
    @Environment(\.libraryStore) private var library

    public init(viewModel: @autoclosure @escaping () -> SearchViewModel) {
        _viewModel = State(wrappedValue: viewModel())
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ShoutKitSpacing.medium) {
                content
            }
            .padding(.horizontal, ShoutKitSpacing.medium)
            .padding(.vertical, ShoutKitSpacing.medium)
        }
        .background(Color.shoutKitBackground)
        .searchable(text: $viewModel.query, prompt: "Stations, genres")
        .task {
            await viewModel.loadGenres()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            browseGenres
        case .searching:
            ProgressView("Searching")
                .frame(maxWidth: .infinity, minHeight: 200)
        case let .results(stations):
            resultsList(stations)
        case .empty:
            ContentUnavailableView.search
        case let .failed(error):
            ContentUnavailableView("Search Unavailable", systemImage: "wifi.exclamationmark", description: Text(error.localizedDescription))
                .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    @ViewBuilder
    private var browseGenres: some View {
        if viewModel.genres.isEmpty {
            ContentUnavailableView(
                "Find your sound",
                systemImage: "magnifyingglass",
                description: Text("Search for stations by name or genre.")
            )
            .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            SectionHeaderView(String(localized: "Browse by Genre", bundle: .module))
            FlowChips(genres: viewModel.genres) { genre in
                viewModel.selectGenre(genre)
            }
        }
    }

    private func resultsList(_ stations: [Station]) -> some View {
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

/// A simple wrapping row of genre chips.
private struct FlowChips: View {
    let genres: [Genre]
    let onSelect: (Genre) -> Void

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: ShoutKitSpacing.small)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: ShoutKitSpacing.small) {
            ForEach(genres) { genre in
                Button {
                    onSelect(genre)
                } label: {
                    Text(genre.name)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                }
                .buttonStyle(.glass)
            }
        }
    }
}
