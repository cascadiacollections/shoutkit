@testable import BrowseFeatureCore
import ConcurrencyExtras
import RadioDirectory
import Testing

/// The first top-stations call is held until ``releaseFirstCall()`` and then
/// fails; every later call succeeds at once.
private actor SequencedTopStationsDirectory: RadioDirectoryProviding {
    private(set) var topStationsCalls = 0
    private var firstCallWaiter: CheckedContinuation<Void, Never>?
    private var firstCallReleased = false

    func releaseFirstCall() {
        firstCallReleased = true
        firstCallWaiter?.resume()
        firstCallWaiter = nil
    }

    func genres() async throws(RadioDirectoryError) -> [Genre] {
        [Genre(name: "Jazz")]
    }

    func topStations(limit _: Int) async throws(RadioDirectoryError) -> [Station] {
        topStationsCalls += 1
        if topStationsCalls == 1 {
            if firstCallReleased == false {
                await withCheckedContinuation { firstCallWaiter = $0 }
            }
            throw .transport("offline")
        }
        return [.fixture(id: "b", name: "Station B")]
    }

    func searchStations(matching _: String, limit _: Int) async throws(RadioDirectoryError) -> [Station] {
        []
    }

    func stations(inGenre _: String, limit _: Int) async throws(RadioDirectoryError) -> [Station] {
        []
    }

    func streamEndpoint(for _: Station) async throws(RadioDirectoryError) -> StreamEndpoint {
        throw .invalidResponse
    }
}

/// Tests that overlap requests, or wait for a genre load, run inside
/// `withMainSerialExecutor`: the view model's tasks and the fake directory's
/// actor hops then share one FIFO queue, and `Task.megaYield()` lets them run
/// to completion in the same order every time. That replaces a 2-second
/// polling helper and a pair of real 200 ms holds. The hook it sets is
/// process-wide and restored on return, so this suite is `.serialized`, and it
/// is the only one in the target that uses it (DECISIONS.md, 2026-11-28).
@MainActor
@Suite(.serialized)
struct BrowseViewModelTests {
    @Test func `refresh loads spotlight stations and genres`() async {
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

    @Test func `refresh with no stations is empty`() async {
        let directory = FakeRadioDirectory()
        await directory.setTopStationsResult(.success([]))
        let viewModel = BrowseViewModel(directory: directory)

        await viewModel.refresh()

        #expect(viewModel.phase == .empty)
    }

    @Test func `refresh surfaces top stations failure`() async {
        let directory = FakeRadioDirectory()
        await directory.setTopStationsResult(.failure(.httpStatus(500)))
        let viewModel = BrowseViewModel(directory: directory)

        await viewModel.refresh()

        #expect(viewModel.phase == .failed(.httpStatus(500)))
    }

    @Test func `genres failure is non fatal to loaded phase`() async {
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

    @Test func `toggle genre filter loads stations for that genre`() async {
        await withMainSerialExecutor {
            let directory = FakeRadioDirectory()
            let jazzStations: [Station] = [.fixture(id: "j1", name: "Jazz One", genre: "Jazz")]
            await directory.setGenreStations(.success(jazzStations), forGenre: "Jazz")
            let viewModel = BrowseViewModel(directory: directory)

            viewModel.toggleGenreFilter("Jazz")
            #expect(viewModel.selectedGenre == "Jazz")
            #expect(viewModel.genrePhase == .loading)

            await Task.megaYield()

            #expect(viewModel.genrePhase == .loaded(jazzStations))
        }
    }

    @Test func `toggling same genre twice clears the filter`() async {
        await withMainSerialExecutor {
            let directory = FakeRadioDirectory()
            await directory.setGenreStations(.success([.fixture(id: "j1", name: "Jazz One")]), forGenre: "Jazz")
            let viewModel = BrowseViewModel(directory: directory)

            viewModel.toggleGenreFilter("Jazz")
            await Task.megaYield()
            #expect(viewModel.genrePhase != .loading)
            viewModel.toggleGenreFilter("Jazz")

            #expect(viewModel.selectedGenre == nil)
            #expect(viewModel.genrePhase == nil)
        }
    }

    @Test func `stale prior genre response is discarded after switching selection`() async {
        await withMainSerialExecutor {
            let directory = FakeRadioDirectory()
            // "Jazz" is held until after the user has switched to "Rock" (which
            // resolves immediately). The guard in toggleGenreFilter should keep
            // Rock's result from being clobbered when Jazz finally answers.
            let rockStations: [Station] = [.fixture(id: "r1", name: "Rock One")]
            await directory.setGenreStations(.success([.fixture(id: "j1", name: "Jazz One")]), forGenre: "Jazz")
            await directory.holdGenreStations(forGenre: "Jazz")
            await directory.setGenreStations(.success(rockStations), forGenre: "Rock")
            let viewModel = BrowseViewModel(directory: directory)

            viewModel.toggleGenreFilter("Jazz")
            viewModel.toggleGenreFilter("Rock")
            await Task.megaYield()
            #expect(await directory.genreStationsCallCount == 2, "both lookups reached the directory")
            #expect(viewModel.genrePhase == .loaded(rockStations))

            await directory.releaseGenreStations(forGenre: "Jazz")
            await Task.megaYield()

            #expect(viewModel.selectedGenre == "Rock")
            #expect(viewModel.genrePhase == .loaded(rockStations))
        }
    }

    @Test func `reloading the selected genre fetches again without clearing it`() async {
        await withMainSerialExecutor {
            let directory = FakeRadioDirectory()
            let jazzStations: [Station] = [.fixture(id: "j1", name: "Jazz One", genre: "Jazz")]
            await directory.setGenreStations(.success(jazzStations), forGenre: "Jazz")
            let viewModel = BrowseViewModel(directory: directory)

            viewModel.toggleGenreFilter("Jazz")
            await Task.megaYield()
            viewModel.reloadGenreFilter()

            #expect(viewModel.selectedGenre == "Jazz")
            #expect(viewModel.genrePhase == .loading)

            await Task.megaYield()
            #expect(viewModel.genrePhase == .loaded(jazzStations))
            #expect(await directory.genreStationsCallCount == 2)
        }
    }

    @Test func `older refresh failure does not override newer loaded result`() async {
        await withMainSerialExecutor {
            let directory = SequencedTopStationsDirectory()
            let viewModel = BrowseViewModel(directory: directory)

            let first = Task { await viewModel.refresh() }
            await Task.megaYield()
            #expect(await directory.topStationsCalls == 1, "the first refresh is in flight")
            await viewModel.refresh()
            await directory.releaseFirstCall()
            await first.value

            guard case let .loaded(content) = viewModel.phase else {
                Issue.record("Expected .loaded after newer refresh, got \(viewModel.phase)")
                return
            }
            #expect(content.stations.map(\.id) == ["b"])
        }
    }
}
