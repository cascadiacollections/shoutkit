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

    /// The same whitespace edit as above, but landing *while* the search is
    /// still running — the case that used to strand the spinner: the didSet
    /// cancelled the in-flight task before deciding the query was a duplicate,
    /// so nothing ever published a phase and nothing re-issued the search.
    @Test func whitespaceEditDuringAnInFlightSearchStillPublishesResults() async {
        let directory = FakeRadioDirectory()
        let stations: [Station] = [.fixture(id: "a", name: "Station A")]
        await directory.setSearchStationsResult(.success(stations))
        await directory.setSearchDelay(.milliseconds(400))
        let viewModel = SearchViewModel(directory: directory)

        viewModel.query = "jazz"
        await waitUntil { viewModel.phase == .searching }

        viewModel.query = "jazz "

        await waitUntil { viewModel.phase != .searching }

        #expect(viewModel.phase == .results(stations))
        let callCount = await directory.searchCallCount
        #expect(callCount == 1)
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

    /// A chip tap asks the directory for stations *tagged* Jazz, not stations
    /// *named* Jazz — the two return very different lists, and the name search
    /// is the wrong one for a genre chip.
    @Test func selectGenreBrowsesTheGenreRatherThanSearchingItsName() async {
        let directory = FakeRadioDirectory()
        let stations: [Station] = [.fixture(id: "a", name: "Blue Note Radio", genre: "Jazz")]
        await directory.setSearchStationsResult(.success(stations))
        let viewModel = SearchViewModel(directory: directory)

        viewModel.selectGenre(Genre(name: "Jazz"))

        await waitUntil { viewModel.phase != .idle && viewModel.phase != .searching }

        #expect(viewModel.phase == .results(stations))
        #expect(viewModel.activeGenre == Genre(name: "Jazz"))
        let genreQueries = await directory.genreStationQueries
        let nameQueries = await directory.searchedQueries
        #expect(genreQueries == ["Jazz"])
        #expect(nameQueries.isEmpty)
    }

    /// A directory tag can arrive padded. Storing the raw name while comparing
    /// trimmed values used to make the chip clear its own `activeGenre` on the way
    /// in, silently demoting the browse to a name search.
    @Test func aGenreNameWithStrayWhitespaceStillBrowsesTheGenre() async {
        let directory = FakeRadioDirectory()
        await directory.setSearchStationsResult(.success([.fixture(id: "a", name: "Blue Note Radio")]))
        let viewModel = SearchViewModel(directory: directory)

        viewModel.selectGenre(Genre(name: "  Jazz  "))

        await waitUntil { viewModel.phase != .idle && viewModel.phase != .searching }

        #expect(viewModel.query == "Jazz")
        #expect(viewModel.activeGenre == Genre(name: "  Jazz  "))
        let genreQueries = await directory.genreStationQueries
        let nameQueries = await directory.searchedQueries
        #expect(genreQueries == ["Jazz"])
        #expect(nameQueries.isEmpty)
    }

    /// Tapping the chip a second time can't rely on `query`'s `didSet` — the text
    /// is already there — so it has to re-issue the request itself.
    @Test func selectingTheSameGenreTwiceRepeatsTheGenreQuery() async {
        let directory = FakeRadioDirectory()
        await directory.setSearchStationsResult(.success([.fixture(id: "a", name: "Blue Note Radio")]))
        let viewModel = SearchViewModel(directory: directory)

        viewModel.selectGenre(Genre(name: "Jazz"))
        await waitUntil { viewModel.phase != .idle && viewModel.phase != .searching }
        viewModel.selectGenre(Genre(name: "Jazz"))
        await waitUntilAsync { await directory.genreStationQueries.count == 2 }

        let genreQueries = await directory.genreStationQueries
        #expect(genreQueries == ["Jazz", "Jazz"])
    }

    /// Editing the field abandons the genre: the text no longer describes a chip,
    /// so the request goes back to being a name search.
    @Test func typingOverAGenreReturnsToNameSearch() async {
        let directory = FakeRadioDirectory()
        await directory.setSearchStationsResult(.success([.fixture(id: "a", name: "Jazzy FM")]))
        let viewModel = SearchViewModel(directory: directory)

        viewModel.selectGenre(Genre(name: "Jazz"))
        await waitUntil { viewModel.phase != .idle && viewModel.phase != .searching }

        viewModel.query = "Jazzy"
        await waitUntilAsync { await directory.searchedQueries.isEmpty == false }

        #expect(viewModel.activeGenre == nil)
        let genreQueries = await directory.genreStationQueries
        let nameQueries = await directory.searchedQueries
        #expect(genreQueries == ["Jazz"])
        #expect(nameQueries == ["Jazzy"])
    }

    @Test func retryReissuesTheGenreQueryRatherThanANameSearch() async {
        let directory = FakeRadioDirectory()
        await directory.setSearchStationsResult(.failure(.httpStatus(503)))
        let viewModel = SearchViewModel(directory: directory)

        viewModel.selectGenre(Genre(name: "Jazz"))
        await waitUntil { viewModel.phase == .failed(.httpStatus(503)) }

        viewModel.retry()
        await waitUntilAsync { await directory.genreStationQueries.count == 2 }

        let genreQueries = await directory.genreStationQueries
        let nameQueries = await directory.searchedQueries
        #expect(genreQueries == ["Jazz", "Jazz"])
        #expect(nameQueries.isEmpty)
    }

    @Test func retryDoesNothingWithAnEmptyField() async {
        let directory = FakeRadioDirectory()
        let viewModel = SearchViewModel(directory: directory)

        viewModel.retry()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.phase == .idle)
        let callCount = await directory.searchCallCount
        #expect(callCount == 0)
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
