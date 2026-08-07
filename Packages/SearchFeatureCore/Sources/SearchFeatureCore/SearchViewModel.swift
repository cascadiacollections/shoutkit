import AsyncAlgorithms
import FactoryKit
import Foundation
import Observation
import RadioDirectory

public enum SearchPhase: Equatable, Sendable {
    case idle
    case searching
    case results([Station])
    case empty
    case failed(RadioDirectoryError)
}

// Explicitly @MainActor (not just the target's default isolation): the
// isolated deinit below requires the class itself to carry the actor
// annotation.
@MainActor
@Observable
public final class SearchViewModel {
    private enum Configuration {
        static let resultLimit = 40
    }

    public var query: String = "" {
        didSet {
            guard query != oldValue else { return }

            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            // An edit that leaves the *trimmed* query unchanged (a trailing
            // space, an autocorrection, a paste with surrounding whitespace)
            // isn't a new search — and must not cancel the running one either.
            // Cancelling above this guard stranded `phase` on `.searching`
            // forever: the in-flight task returned on its cancellation check
            // without publishing, and nothing re-issued it because the query
            // was a duplicate. Hence the cancel lives below the guard.
            guard trimmed != lastTrimmedQuery else { return }

            // Typing over a genre chip's text turns the request back into a name
            // search. Set before `runSearch` can see it, so the very edit that
            // abandons the genre doesn't get answered as one.
            if trimmed != activeGenreQuery {
                activeGenre = nil
            }

            searchTask?.cancel()
            if trimmed.isEmpty {
                // Clearing resets instantly; only real queries wait out the
                // debounce. The empty value still flows through the stream so
                // it supersedes any keystroke waiting in the debounce window.
                phase = .idle
            }
            lastTrimmedQuery = trimmed
            queries.yield(trimmed)
        }
    }

    public private(set) var phase: SearchPhase = .idle
    public private(set) var genres: [Genre] = []
    public private(set) var genreLoadError: RadioDirectoryError?
    public var filters: StationSearchFilters = .none {
        didSet {
            guard filters != oldValue else { return }
            rerunCurrentQueryForFilterChange()
        }
    }
    /// The genre chip whose stations are on screen, if the current results came
    /// from a chip rather than from typing. Drives the chip's selected state and
    /// picks the genre query over the name search below.
    public private(set) var activeGenre: Genre?

    /// ``activeGenre``'s name in the form queries take — trimmed, like everything
    /// that flows through `query`. The whole `Genre` is what's stored, not just
    /// this string, so the chip grid can match on identity (including
    /// `stationCount`) to decide which chip renders selected.
    private var activeGenreQuery: String? {
        activeGenre?.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ObservationIgnored private let directory: any RadioDirectoryProviding
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private let queries: AsyncStream<String>.Continuation
    @ObservationIgnored private var lastTrimmedQuery = ""

    public init(directory: any RadioDirectoryProviding = Container.shared.radioDirectory()) {
        self.directory = directory

        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        queries = continuation
        debounceTask = Task { [weak self] in
            // The debounce emits only the latest value after 300 ms of
            // keyboard quiet, so a superseded keystroke never hits the network.
            for await query in stream.debounce(for: .milliseconds(300)) {
                guard let self else { return }
                guard query.isEmpty == false else { continue }
                self.runSearch(query)
            }
        }
    }

    isolated deinit {
        searchTask?.cancel()
        debounceTask?.cancel()
    }

    public func loadGenres() async {
        do {
            genres = try await directory.genres()
            genreLoadError = nil
        } catch let error as RadioDirectoryError {
            genres = []
            genreLoadError = error
        } catch {
            genres = []
            genreLoadError = .transport(error.localizedDescription)
        }
    }

    /// Browses a genre. The name lands in the search field so the results are
    /// labeled and the field's own Clear button gets you back out — but the
    /// request itself goes to the directory's genre/tag query, not to the name
    /// search. Tapping "Jazz" used to return stations *called* Jazz.
    public func selectGenre(_ genre: Genre) {
        activeGenre = genre

        let trimmed = genre.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.trimmingCharacters(in: .whitespacesAndNewlines) != trimmed else {
            // The field already holds this text — the same chip tapped twice, or
            // a genre the user happened to type — so `query`'s `didSet` won't
            // fire. Run it here rather than leaving the chip visibly inert.
            runSearch(trimmed)
            return
        }
        // The trimmed name, not the raw one: every other value that reaches
        // `query` gets compared in trimmed form, so a directory tag arriving with
        // stray whitespace would fail `activeGenreQuery`'s check on the way in and
        // silently downgrade its own chip to a name search.
        query = trimmed
    }

    /// Re-runs whatever is currently in the field, keeping the *kind* of request
    /// intact — retrying a failed genre chip must not quietly become a name
    /// search for the genre's name.
    public func retry() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        runSearch(trimmed)
    }

    public func clearFilters() {
        filters = .none
    }

    private func runSearch(_ query: String) {
        searchTask?.cancel()
        // Only show the spinner once the debounce actually fires; setting it
        // per keystroke makes results flicker while the user is typing.
        phase = .searching
        searchTask = Task { [weak self] in
            await self?.performSearch(query)
        }
    }

    private func performSearch(_ query: String) async {
        do {
            let stations = try await fetchStations(matching: query)
            guard Task.isCancelled == false else { return }
            phase = stations.isEmpty ? .empty : .results(stations)
        } catch {
            guard Task.isCancelled == false else { return }
            phase = .failed(error)
        }
    }

    /// A chip tap asks the directory what's *tagged* with a genre; typing asks
    /// what's *named* like the query. Same phase either way — two different
    /// questions with the same shape of answer.
    private func fetchStations(matching query: String) async throws(RadioDirectoryError) -> [Station] {
        let normalizedFilters = filters.normalized
        if let activeGenreQuery, activeGenreQuery == query {
            return try await directory.stations(
                inGenre: activeGenreQuery,
                limit: Configuration.resultLimit,
                filters: normalizedFilters
            )
        }
        return try await directory.searchStations(
            matching: query,
            limit: Configuration.resultLimit,
            filters: normalizedFilters
        )
    }

    private func rerunCurrentQueryForFilterChange() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty == false {
            runSearch(trimmedQuery)
            return
        }
        if let activeGenreQuery {
            runSearch(activeGenreQuery)
        }
    }
}
