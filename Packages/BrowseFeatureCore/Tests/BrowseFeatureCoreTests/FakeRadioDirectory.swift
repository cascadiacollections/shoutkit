import Foundation
import RadioDirectory

/// Scriptable `RadioDirectoryProviding` double. Each call site configures the
/// result it wants and, for the genre lookup, an optional per-genre delay so
/// tests can force a specific interleaving (e.g. an older request resolving
/// after a newer one).
actor FakeRadioDirectory: RadioDirectoryProviding {
    var genresResult: Result<[Genre], RadioDirectoryError> = .success([])
    var topStationsResult: Result<[Station], RadioDirectoryError> = .success([])
    var searchStationsResult: Result<[Station], RadioDirectoryError> = .success([])
    var genreStationsResultsByGenre: [String: Result<[Station], RadioDirectoryError>] = [:]
    var genreStationsDelayByGenre: [String: Duration] = [:]

    private(set) var genreStationsCallCount = 0

    func setGenresResult(_ result: Result<[Genre], RadioDirectoryError>) {
        genresResult = result
    }

    func setTopStationsResult(_ result: Result<[Station], RadioDirectoryError>) {
        topStationsResult = result
    }

    func setGenreStations(
        _ result: Result<[Station], RadioDirectoryError>,
        forGenre genre: String,
        delay: Duration? = nil
    ) {
        genreStationsResultsByGenre[genre] = result
        if let delay {
            genreStationsDelayByGenre[genre] = delay
        }
    }

    func genres() async throws(RadioDirectoryError) -> [Genre] {
        switch genresResult {
        case let .success(genres): return genres
        case let .failure(error): throw error
        }
    }

    func topStations(limit: Int) async throws(RadioDirectoryError) -> [Station] {
        switch topStationsResult {
        case let .success(stations): return stations
        case let .failure(error): throw error
        }
    }

    func searchStations(matching query: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        switch searchStationsResult {
        case let .success(stations): return stations
        case let .failure(error): throw error
        }
    }

    func stations(inGenre genre: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        genreStationsCallCount += 1
        if let delay = genreStationsDelayByGenre[genre] {
            try? await Task.sleep(for: delay)
        }
        switch genreStationsResultsByGenre[genre] ?? .success([]) {
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
