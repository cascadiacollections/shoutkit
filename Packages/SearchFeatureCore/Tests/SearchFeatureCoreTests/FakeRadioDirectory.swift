import Foundation
import RadioDirectory

/// Scriptable `RadioDirectoryProviding` double for SearchViewModel's tests.
/// Tracks search invocations so debounce/coalescing behavior can be asserted.
actor FakeRadioDirectory: RadioDirectoryProviding {
    var genresResult: Result<[Genre], RadioDirectoryError> = .success([])
    var searchStationsResult: Result<[Station], RadioDirectoryError> = .success([])
    /// Holds each search open so a test can act while one is genuinely in
    /// flight (rather than only before or after it).
    var searchDelay: Duration = .zero

    private(set) var searchCallCount = 0
    private(set) var searchedQueries: [String] = []
    private(set) var searchedFilters: [StationSearchFilters] = []
    /// Genres asked for through the dedicated genre query. Tracked separately
    /// from `searchedQueries` because the whole point of the genre path is that
    /// it is *not* a name search — the protocol's default implementation would
    /// silently make it one.
    private(set) var genreStationQueries: [String] = []
    private(set) var genreStationFilters: [StationSearchFilters] = []

    func setGenresResult(_ result: Result<[Genre], RadioDirectoryError>) {
        genresResult = result
    }

    func setSearchStationsResult(_ result: Result<[Station], RadioDirectoryError>) {
        searchStationsResult = result
    }

    func setSearchDelay(_ delay: Duration) {
        searchDelay = delay
    }

    func genres() async throws(RadioDirectoryError) -> [Genre] {
        switch genresResult {
        case let .success(genres): return genres
        case let .failure(error): throw error
        }
    }

    func topStations(limit: Int) async throws(RadioDirectoryError) -> [Station] {
        []
    }

    func searchStations(matching query: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        try await searchStations(matching: query, limit: limit, filters: .none)
    }

    func searchStations(
        matching query: String,
        limit: Int,
        filters: StationSearchFilters
    ) async throws(RadioDirectoryError) -> [Station] {
        searchCallCount += 1
        searchedQueries.append(query)
        searchedFilters.append(filters)
        if searchDelay > .zero {
            try? await Task.sleep(for: searchDelay)
        }
        switch searchStationsResult {
        case let .success(stations): return stations
        case let .failure(error): throw error
        }
    }

    func stations(inGenre genre: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        try await stations(inGenre: genre, limit: limit, filters: .none)
    }

    func stations(
        inGenre genre: String,
        limit: Int,
        filters: StationSearchFilters
    ) async throws(RadioDirectoryError) -> [Station] {
        genreStationQueries.append(genre)
        genreStationFilters.append(filters)
        if searchDelay > .zero {
            try? await Task.sleep(for: searchDelay)
        }
        switch searchStationsResult {
        case let .success(stations): return stations
        case let .failure(error): throw error
        }
    }

    func streamEndpoint(for station: Station) async throws(RadioDirectoryError) -> StreamEndpoint {
        throw .invalidResponse
    }
}

extension Station {
    static func fixture(id: String, name: String, genre: String = "Test", listenerCount: Int = 0) -> Station {
        Station(id: id, name: name, genre: genre, listenerCount: listenerCount)
    }
}

/// Polls until `condition` holds or the deadline passes.
///
/// The deadline only bounds the *failing* path — this returns as soon as the
/// condition is true — so a generous budget costs a passing run nothing and
/// buys flake resistance. That matters because these cases wait out a real
/// 300 ms debounce (and, in the in-flight whitespace case, a further scripted
/// search delay) while CI runs the suite in parallel with dozens of others.
@MainActor
func waitUntil(_ condition: () -> Bool, upTo seconds: TimeInterval = 5) async {
    let deadline = Date().addingTimeInterval(seconds)
    while condition() == false, Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// `waitUntil` for conditions that read the fake directory's actor-isolated call
/// log. Deliberately a separate name rather than an overload: a trailing-closure
/// call would be ambiguous between the two, since the sync version's only other
/// parameter has a default.
@MainActor
func waitUntilAsync(_ condition: () async -> Bool, upTo seconds: TimeInterval = 5) async {
    let deadline = Date().addingTimeInterval(seconds)
    while await condition() == false, Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
