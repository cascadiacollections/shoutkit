import RadioDirectory
import Testing

@testable import BrowseFeatureCore

@MainActor
struct BrowseViewModelTests {
    @Test func refreshLoadsSpotlightStationsAndGenres() async {
        let directory = FakeRadioDirectory()
        let stations: [Station] = [.fixture(id: "a", name: "Station A"), .fixture(id: "b", name: "Station B")]
        await directory.setTopStationsResult(.success(stations))
        await directory.setGenresResult(.success([Genre(name: "Jazz")]))
        let viewModel = BrowseViewModel(directory: directory)

        await viewModel.refresh()

        guard case let .loaded(content) = viewModel.phase else {
            Issue.record("Expected .loaded, got \(viewModel.phase)")
            return
        }
        #expect(content.spotlight?.id == "a")
        #expect(content.stations.map(\.id) == ["a", "b"])
        #expect(content.genres == [Genre(name: "Jazz")])
        #expect(viewModel.genresError == nil)
    }

    @Test func refreshWithNoStationsIsEmpty() async {
        let directory = FakeRadioDirectory()
        await directory.setTopStationsResult(.success([]))
        let viewModel = BrowseViewModel(directory: directory)

        await viewModel.refresh()

        #expect(viewModel.phase == .empty)
    }

    @Test func refreshSurfacesTopStationsFailure() async {
        let directory = FakeRadioDirectory()
        await directory.setTopStationsResult(.failure(.httpStatus(500)))
        let viewModel = BrowseViewModel(directory: directory)

        await viewModel.refresh()

        #expect(viewModel.phase == .failed(.httpStatus(500)))
    }

    @Test func genresFailureIsNonFatalToLoadedPhase() async {
        let directory = FakeRadioDirectory()
        await directory.setTopStationsResult(.success([.fixture(id: "a", name: "Station A")]))
        await directory.setGenresResult(.failure(.invalidResponse))
        let viewModel = BrowseViewModel(directory: directory)

        await viewModel.refresh()

        guard case .loaded = viewModel.phase else {
            Issue.record("Expected .loaded despite genres failure, got \(viewModel.phase)")
            return
        }
        #expect(viewModel.genresError == .invalidResponse)
    }

    @Test func toggleGenreFilterLoadsStationsForThatGenre() async {
        let directory = FakeRadioDirectory()
        let jazzStations: [Station] = [.fixture(id: "j1", name: "Jazz One", genre: "Jazz")]
        await directory.setGenreStations(.success(jazzStations), forGenre: "Jazz")
        let viewModel = BrowseViewModel(directory: directory)

        viewModel.toggleGenreFilter("Jazz")
        #expect(viewModel.selectedGenre == "Jazz")
        #expect(viewModel.genrePhase == .loading)

        await waitUntil { viewModel.genrePhase != .loading }

        #expect(viewModel.genrePhase == .loaded(jazzStations))
    }

    @Test func togglingSameGenreTwiceClearsTheFilter() async {
        let directory = FakeRadioDirectory()
        await directory.setGenreStations(.success([.fixture(id: "j1", name: "Jazz One")]), forGenre: "Jazz")
        let viewModel = BrowseViewModel(directory: directory)

        viewModel.toggleGenreFilter("Jazz")
        await waitUntil { viewModel.genrePhase != .loading }
        viewModel.toggleGenreFilter("Jazz")

        #expect(viewModel.selectedGenre == nil)
        #expect(viewModel.genrePhase == nil)
    }

    @Test func stalePriorGenreResponseIsDiscardedAfterSwitchingSelection() async {
        let directory = FakeRadioDirectory()
        // "Jazz" resolves slowly; by the time it does, the user has already
        // switched to "Rock" (which resolves immediately). The guard in
        // toggleGenreFilter should keep Rock's result from being clobbered.
        await directory.setGenreStations(
            .success([.fixture(id: "j1", name: "Jazz One")]),
            forGenre: "Jazz",
            delay: .milliseconds(200)
        )
        await directory.setGenreStations(.success([.fixture(id: "r1", name: "Rock One")]), forGenre: "Rock")
        let viewModel = BrowseViewModel(directory: directory)

        viewModel.toggleGenreFilter("Jazz")
        viewModel.toggleGenreFilter("Rock")

        await waitUntil { viewModel.genrePhase != .loading }
        // Give the slow "Jazz" response a chance to land, if it were going to.
        try? await Task.sleep(for: .milliseconds(300))

        #expect(viewModel.selectedGenre == "Rock")
        #expect(viewModel.genrePhase == .loaded([.fixture(id: "r1", name: "Rock One")]))
    }
}
