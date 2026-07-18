import Foundation
import RadioDirectory

/// Scriptable `RadioDirectoryProviding` double for SearchViewModel's tests.
/// Tracks search invocations so debounce/coalescing behavior can be asserted.
actor FakeRadioDirectory: RadioDirectoryProviding {
    var genresResult: Result<[Genre], RadioDirectoryError> = .success([])
    var searchStationsResult: Result<[Station], RadioDirectoryError> = .success([])

    private(set) var searchCallCount = 0
    private(set) var searchedQueries: [String] = []

    func setGenresResult(_ result: Result<[Genre], RadioDirectoryError>) {
        genresResult = result
    }

    func setSearchStationsResult(_ result: Result<[Station], RadioDirectoryError>) {
        searchStationsResult = result
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
        searchCallCount += 1
        searchedQueries.append(query)
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
@MainActor
func waitUntil(_ condition: () -> Bool, upTo seconds: TimeInterval = 2) async {
    let deadline = Date().addingTimeInterval(seconds)
    while condition() == false, Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
