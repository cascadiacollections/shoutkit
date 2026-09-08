import DesignSystem
import Persistence
import Playback
import RadioDirectory
import SearchFeatureCore
import SwiftUI

public struct SearchView: View {
    @State private var viewModel: SearchViewModel
    @State private var isFilterSheetPresented = false
    @Environment(\.playbackController) private var playback
    @Environment(\.libraryStore) private var library
    @Environment(\.displayScale) private var displayScale
    // Switching into the Search tab should drop the keyboard straight into the
    // search field, matching Apple Music/Podcasts — nobody switches to Search
    // to look at it.
    @FocusState private var isSearchFieldFocused: Bool
    // Bumped by the caller when the Search tab is re-tapped while already
    // selected, so re-selecting Search also refocuses the field — `onAppear`
    // alone only covers the first switch into this tab.
    private let reactivationToken: Int

    public init(viewModel: @autoclosure @escaping () -> SearchViewModel, reactivationToken: Int = 0) {
        _viewModel = State(wrappedValue: viewModel())
        self.reactivationToken = reactivationToken
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
        .searchFocused($isSearchFieldFocused)
        .onAppear {
            isSearchFieldFocused = true
        }
        .onChange(of: reactivationToken) { _, _ in
            isSearchFieldFocused = true
        }
        .task {
            await viewModel.loadGenres()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isFilterSheetPresented = true
                } label: {
                    Image(systemName: viewModel.filters.normalized.isActive
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel(String(localized: "Search Filters", bundle: .module))
            }
        }
        .sheet(isPresented: $isFilterSheetPresented) {
            SearchFilterSheet(filters: $viewModel.filters) {
                viewModel.clearFilters()
            }
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
            emptyStateView
        case let .failed(error):
            DirectoryUnavailableView(
                title: String(localized: "Search Unavailable", bundle: .module),
                error: error,
                minHeight: 200
            ) {
                viewModel.retry()
            }
        }
    }

    @ViewBuilder
    private var browseGenres: some View {
        if viewModel.genres.isEmpty {
            if let error = viewModel.genreLoadError {
                DirectoryUnavailableView(
                    title: String(localized: "Couldn't Load Genres", bundle: .module),
                    error: error
                ) {
                    Task { await viewModel.loadGenres() }
                }
            } else {
                ContentUnavailableView(
                    "Find your sound",
                    systemImage: "magnifyingglass",
                    description: Text("Search for stations by name or genre.")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            }
        } else {
            SectionHeaderView(String(localized: "Browse by Genre", bundle: .module))
            GenreChips(genres: viewModel.genres, selected: viewModel.activeGenre) { genre in
                viewModel.selectGenre(genre)
            }
        }
    }

    private func resultsList(_ stations: [Station]) -> some View {
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

    @ViewBuilder
    private var emptyStateView: some View {
        if viewModel.filters.normalized.isActive {
            ContentUnavailableView {
                Label(
                    String(localized: "No matching stations", bundle: .module),
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            } description: {
                Text(
                    String(
                        format: String(localized: "Active filters: %@", bundle: .module),
                        activeFilterSummary
                    )
                )
            } actions: {
                Button(String(localized: "Clear Filters", bundle: .module)) {
                    viewModel.clearFilters()
                }
            }
        } else {
            ContentUnavailableView.search
        }
    }

    private var activeFilterSummary: String {
        let filters = viewModel.filters.normalized
        var parts: [String] = []
        if let bitrateMin = filters.bitrateMin {
            parts.append(
                String(
                    format: String(localized: "%d kbps or higher", bundle: .module),
                    bitrateMin
                )
            )
        }
        if let bitrateMax = filters.bitrateMax {
            parts.append(
                String(
                    format: String(localized: "%d kbps or lower", bundle: .module),
                    bitrateMax
                )
            )
        }
        if let tag = filters.tag {
            parts.append(
                String(
                    format: String(localized: "Tag: %@", bundle: .module),
                    tag
                )
            )
        }
        if let countryCode = filters.countryCode {
            parts.append(
                String(
                    format: String(localized: "Country: %@", bundle: .module),
                    countryCode
                )
            )
        }
        return parts.joined(separator: ", ")
    }
}

/// A wrapping grid of genre chips, with the browsed one held selected so the
/// results below are attributable to a tap you can see you made.
private struct GenreChips: View {
    let genres: [Genre]
    let selected: Genre?
    let onSelect: (Genre) -> Void

    /// Identity for the one prominent chip, so the selection can travel.
    @Namespace private var chipGlass

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: ShoutKitSpacing.small)]

    /// The grid is a `GlassEffectContainer` so the chips are one piece of glass
    /// to the system rather than a dozen unrelated ones. That is what lets the
    /// selected chip's glass *move* to the chip you tapped instead of one
    /// fading out while another fades in — see `chip(_:)`.
    ///
    /// `spacing: 0`, not the grid's own `ShoutKitSpacing.small`. A container
    /// merges glass shapes that fall within `spacing` of each other, and these
    /// chips sit 10 pt apart: at the grid's own spacing a row of them would fuse
    /// into one bar. Same call, and the same reason, as the Now Playing
    /// transport row.
    var body: some View {
        GlassEffectContainer(spacing: 0) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: ShoutKitSpacing.small) {
                ForEach(genres) { genre in
                    chip(genre)
                        .accessibilityAddTraits(genre == selected ? .isSelected : [])
                }
            }
        }
        // Without this the glass arrives at the new chip instantly and there is
        // nothing to see. The morph is the point, so it gets an explicit curve
        // rather than inheriting whatever the caller happens to be animating.
        .animation(.smooth(duration: 0.3), value: selected)
    }

    // Two branches rather than one style value: `ButtonStyle` has no type-erased
    // box, so the choice has to be made in the view tree.
    @ViewBuilder
    private func chip(_ genre: Genre) -> some View {
        let label = Text(genre.name)
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .lineLimit(1)

        if genre == selected {
            Button { onSelect(genre) } label: { label }
                .buttonStyle(.glassProminent)
                // Exactly one chip carries this at a time, which is the whole
                // mechanism: when `selected` changes the same glass identity
                // turns up at a different place in the grid, so the container
                // moves the glass there rather than drawing a second one. A
                // bare literal because it appears once — an ID that has one
                // call site cannot disagree with itself.
                .glassEffectID("genre-selection", in: chipGlass)
        } else {
            Button { onSelect(genre) } label: { label }
                .buttonStyle(.glass)
        }
    }
}

private struct SearchFilterSheet: View {
    @Binding var filters: StationSearchFilters
    let onClear: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let bitrateOptions: [Int] = [64, 96, 128, 160, 192, 256, 320]

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Bitrate", bundle: .module)) {
                    Picker(
                        String(localized: "Minimum Bitrate", bundle: .module),
                        selection: minimumBitrateBinding
                    ) {
                        Text(String(localized: "Any", bundle: .module)).tag(Int?.none)
                        ForEach(bitrateOptions, id: \.self) { bitrate in
                            Text("\(bitrate) kbps").tag(Optional(bitrate))
                        }
                    }

                    Picker(
                        String(localized: "Maximum Bitrate", bundle: .module),
                        selection: maximumBitrateBinding
                    ) {
                        Text(String(localized: "Any", bundle: .module)).tag(Int?.none)
                        ForEach(bitrateOptions, id: \.self) { bitrate in
                            Text("\(bitrate) kbps").tag(Optional(bitrate))
                        }
                    }
                }

                Section {
                    TextField(String(localized: "Tag", bundle: .module), text: tagBinding)
                    TextField(
                        String(localized: "Country Code", bundle: .module),
                        text: countryCodeBinding
                    )
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                }
            }
            .navigationTitle(String(localized: "Search Filters", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if filters.normalized.isActive {
                        Button(String(localized: "Clear Filters", bundle: .module)) {
                            onClear()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done", bundle: .module)) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var minimumBitrateBinding: Binding<Int?> {
        Binding(
            get: { filters.bitrateMin },
            set: { filters.bitrateMin = $0 }
        )
    }

    private var maximumBitrateBinding: Binding<Int?> {
        Binding(
            get: { filters.bitrateMax },
            set: { filters.bitrateMax = $0 }
        )
    }

    private var tagBinding: Binding<String> {
        Binding(
            get: { filters.tag ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                filters.tag = trimmed.isEmpty ? nil : newValue
            }
        )
    }

    private var countryCodeBinding: Binding<String> {
        Binding(
            get: { filters.countryCode ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                filters.countryCode = trimmed.isEmpty ? nil : newValue
            }
        )
    }
}
