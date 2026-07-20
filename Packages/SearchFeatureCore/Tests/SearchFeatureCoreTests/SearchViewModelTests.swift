import RadioDirectory
import Testing

@testable import SearchFeatureCore

@MainActor
struct SearchViewModelTests {
    @Test func initialPhaseIsIdle() {
        let viewModel = SearchViewModel(directory: FakeRadioDirectory())
        #expect(viewModel.phase == .idle)
    }

    @Test func typingSettlesToResultsAfterTheDebounceWindow() async {
        let directory = FakeRadioDirectory()
        let stations: [Station] = [.fixture(id: "a", name: "Station A")]
        await directory.setSearchStationsResult(.success(stations))
        let viewModel = SearchViewModel(directory: directory)

        viewModel.query = "kexp"

        await waitUntil { viewModel.phase != .idle && viewModel.phase != .searching }

        #expect(viewModel.phase == .results(stations))
        let queries = await directory.searchedQueries
        #expect(queries == ["kexp"])
    }

    @Test func rapidRetypingOnlySearchesTheSettledQuery() async {
        let directory = FakeRadioDirectory()
        await directory.setSearchStationsResult(.success([.fixture(id: "a", name: "Station A")]))
        let viewModel = SearchViewModel(directory: directory)

        // Each keystroke arrives well inside the 300ms debounce window, so
        // only the last one should ever reach the directory.
        viewModel.query = "k"
        viewModel.query = "ke"
        viewModel.query = "kex"
        viewModel.query = "kexp"

        await waitUntil { viewModel.phase != .idle && viewModel.phase != .searching }

        let callCount = await directory.searchCallCount
        let queries = await directory.searchedQueries
        #expect(callCount == 1)
        #expect(queries == ["kexp"])
    }

    @Test func whitespaceOnlyQueryChangesDoNotTriggerDuplicateSearch() async {
        let directory = FakeRadioDirectory()
        await directory.setSearchStationsResult(.success([.fixture(id: "a", name: "Station A")]))
        let viewModel = SearchViewModel(directory: directory)

        viewModel.query = "jazz"
        await waitUntil { viewModel.phase != .idle && viewModel.phase != .searching }
        viewModel.query = "jazz "
        try? await Task.sleep(for: .milliseconds(400))

        let callCount = await directory.searchCallCount
        let queries = await directory.searchedQueries
        #expect(callCount == 1)
        #expect(queries == ["jazz"])
    }

    @Test func clearingTheQueryResetsToIdleWithoutSearching() async {
        let directory = FakeRadioDirectory()
        await directory.setSearchStationsResult(.success([.fixture(id: "a", name: "Station A")]))
        let viewModel = SearchViewModel(directory: directory)

        viewModel.query = "kexp"
        await waitUntil { viewModel.phase != .idle && viewModel.phase != .searching }
        viewModel.query = ""

        #expect(viewModel.phase == .idle)
    }

    @Test func emptyResultsProduceEmptyPhase() async {
        let directory = FakeRadioDirectory()
        await directory.setSearchStationsResult(.success([]))
        let viewModel = SearchViewModel(directory: directory)

        viewModel.query = "nonexistent"

        await waitUntil { viewModel.phase != .idle && viewModel.phase != .searching }

        #expect(viewModel.phase == .empty)
    }

    @Test func searchFailureSurfacesAsFailedPhase() async {
        let directory = FakeRadioDirectory()
        await directory.setSearchStationsResult(.failure(.httpStatus(500)))
        let viewModel = SearchViewModel(directory: directory)

        viewModel.query = "kexp"

        await waitUntil { viewModel.phase != .idle && viewModel.phase != .searching }

        #expect(viewModel.phase == .failed(.httpStatus(500)))
    }

    @Test func selectGenreSetsQueryToGenreName() {
        let viewModel = SearchViewModel(directory: FakeRadioDirectory())
        viewModel.selectGenre(Genre(name: "Jazz"))
        #expect(viewModel.query == "Jazz")
    }

    @Test func loadGenresPopulatesGenresOnSuccess() async {
        let directory = FakeRadioDirectory()
        await directory.setGenresResult(.success([Genre(name: "Jazz"), Genre(name: "Rock")]))
        let viewModel = SearchViewModel(directory: directory)

        await viewModel.loadGenres()

        #expect(viewModel.genres == [Genre(name: "Jazz"), Genre(name: "Rock")])
        #expect(viewModel.genreLoadError == nil)
    }

    @Test func loadGenresSurfacesFailureAndClearsGenres() async {
        let directory = FakeRadioDirectory()
        await directory.setGenresResult(.failure(.invalidResponse))
        let viewModel = SearchViewModel(directory: directory)

        await viewModel.loadGenres()

        #expect(viewModel.genres == [])
        #expect(viewModel.genreLoadError == .invalidResponse)
    }
}
