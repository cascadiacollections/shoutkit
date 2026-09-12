import RadioDirectory
@testable import SearchFeatureCore
import Testing

@MainActor
struct SearchViewModelTests {
    @Test func `initial phase is idle`() {
        let viewModel = SearchViewModel(directory: FakeRadioDirectory())
        #expect(viewModel.phase == .idle)
    }

    @Test func `typing settles to results after the debounce window`() async {
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

    @Test func `rapid retyping only searches the settled query`() async {
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

    @Test func `whitespace only query changes do not trigger duplicate search`() async {
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
    @Test func `whitespace edit during an in flight search still publishes results`() async {
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

    @Test func `clearing the query resets to idle without searching`() async {
        let directory = FakeRadioDirectory()
        await directory.setSearchStationsResult(.success([.fixture(id: "a", name: "Station A")]))
        let viewModel = SearchViewModel(directory: directory)

        viewModel.query = "kexp"
        await waitUntil { viewModel.phase != .idle && viewModel.phase != .searching }
        viewModel.query = ""

        #expect(viewModel.phase == .idle)
    }

    @Test func `empty results produce empty phase`() async {
        let directory = FakeRadioDirectory()
        await directory.setSearchStationsResult(.success([]))
        let viewModel = SearchViewModel(directory: directory)

        viewModel.query = "nonexistent"

        await waitUntil { viewModel.phase != .idle && viewModel.phase != .searching }

        #expect(viewModel.phase == .empty)
    }

    @Test func `search failure surfaces as failed phase`() async {
        let directory = FakeRadioDirectory()
        await directory.setSearchStationsResult(.failure(.httpStatus(500)))
        let viewModel = SearchViewModel(directory: directory)

        viewModel.query = "kexp"

        await waitUntil { viewModel.phase != .idle && viewModel.phase != .searching }

        #expect(viewModel.phase == .failed(.httpStatus(500)))
    }

    @Test func `select genre sets query to genre name`() {
        let viewModel = SearchViewModel(directory: FakeRadioDirectory())
        viewModel.selectGenre(Genre(name: "Jazz"))
        #expect(viewModel.query == "Jazz")
    }

    /// A chip tap asks the directory for stations *tagged* Jazz, not stations
    /// *named* Jazz — the two return very different lists, and the name search
    /// is the wrong one for a genre chip.
    @Test func `select genre browses the genre rather than searching its name`() async {
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
    @Test func `a genre name with stray whitespace still browses the genre`() async {
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
    @Test func `selecting the same genre twice repeats the genre query`() async {
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
    @Test func `typing over A genre returns to name search`() async {
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

    @Test func `retry reissues the genre query rather than A name search`() async {
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

    @Test func `retry does nothing with an empty field`() async {
        let directory = FakeRadioDirectory()
        let viewModel = SearchViewModel(directory: directory)

        viewModel.retry()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.phase == .idle)
        let callCount = await directory.searchCallCount
        #expect(callCount == 0)
    }

    @Test func `active filters are passed to name searches`() async {
        let directory = FakeRadioDirectory()
        await directory.setSearchStationsResult(.success([.fixture(id: "a", name: "Station A")]))
        let viewModel = SearchViewModel(directory: directory)
        viewModel.filters = StationSearchFilters(bitrateMin: 128, tag: "jazz", countryCode: "us")

        viewModel.query = "kexp"
        await waitUntil { viewModel.phase != .idle && viewModel.phase != .searching }

        let filters = await directory.searchedFilters
        #expect(filters == [StationSearchFilters(bitrateMin: 128, tag: "jazz", countryCode: "US")])
    }

    @Test func `active filters are passed to genre searches`() async {
        let directory = FakeRadioDirectory()
        await directory.setSearchStationsResult(.success([.fixture(id: "a", name: "Blue Note")]))
        let viewModel = SearchViewModel(directory: directory)
        viewModel.filters = StationSearchFilters(bitrateMax: 192, tag: "live")

        viewModel.selectGenre(Genre(name: "Jazz"))
        await waitUntil { viewModel.phase != .idle && viewModel.phase != .searching }

        let filters = await directory.genreStationFilters
        #expect(filters == [StationSearchFilters(bitrateMax: 192, tag: "live")])
    }

    @Test func `changing filters reruns the current search query`() async {
        let directory = FakeRadioDirectory()
        await directory.setSearchStationsResult(.success([.fixture(id: "a", name: "Station A")]))
        let viewModel = SearchViewModel(directory: directory)

        viewModel.query = "jazz"
        await waitUntil { viewModel.phase != .idle && viewModel.phase != .searching }

        viewModel.filters = StationSearchFilters(bitrateMin: 128)
        await waitUntilAsync { await directory.searchCallCount == 2 }

        let queries = await directory.searchedQueries
        #expect(queries == ["jazz", "jazz"])
    }

    @Test func `load genres populates genres on success`() async {
        let directory = FakeRadioDirectory()
        await directory.setGenresResult(.success([Genre(name: "Jazz"), Genre(name: "Rock")]))
        let viewModel = SearchViewModel(directory: directory)

        await viewModel.loadGenres()

        #expect(viewModel.genres == [Genre(name: "Jazz"), Genre(name: "Rock")])
        #expect(viewModel.genreLoadError == nil)
    }

    @Test func `genre strip is populated before any load`() {
        let viewModel = SearchViewModel(directory: FakeRadioDirectory())

        // The point of the seed: Search paints a usable genre strip on the
        // first frame, without waiting on a directory call that is `async`
        // even when the answer is already cached.
        #expect(viewModel.genres.isEmpty == false)
        #expect(viewModel.genres == Genre.paintTimeDefaults)
        #expect(viewModel.genreLoadError == nil)
    }

    @Test func `load genres surfaces failure and keeps the existing strip`() async {
        let directory = FakeRadioDirectory()
        await directory.setGenresResult(.failure(.invalidResponse))
        let viewModel = SearchViewModel(directory: directory)

        await viewModel.loadGenres()

        // Deliberately not cleared. Emptying the strip traded a working browse
        // affordance for an error message; the seeded tags are real, so a genre
        // is still selectable and a query that cannot reach the network reports
        // it where the user asked for it.
        #expect(viewModel.genres == Genre.paintTimeDefaults)
        #expect(viewModel.genreLoadError == .invalidResponse)
    }
}
