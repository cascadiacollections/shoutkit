import Foundation
import RadioDirectory

/// Scriptable `RadioDirectoryProviding` double. Each call site configures the
/// result it wants and, for the genre lookup, can hold one genre's answer until
/// the test releases it, to force an older request to resolve after a newer one.
actor FakeRadioDirectory: RadioDirectoryProviding {
    var genresResult: Result<[Genre], RadioDirectoryError> = .success([])
    var topStationsResult: Result<[Station], RadioDirectoryError> = .success([])
    var searchStationsResult: Result<[Station], RadioDirectoryError> = .success([])
    var genreStationsResultsByGenre: [String: Result<[Station], RadioDirectoryError>] = [:]
    private var heldGenres: Set<String> = []
    private var genreWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    private(set) var genreStationsCallCount = 0
    private(set) var genresCallCount = 0
    private(set) var topStationsCallCount = 0

    func setGenresResult(_ result: Result<[Genre], RadioDirectoryError>) {
        genresResult = result
    }

    func setTopStationsResult(_ result: Result<[Station], RadioDirectoryError>) {
        topStationsResult = result
    }

    func setGenreStations(_ result: Result<[Station], RadioDirectoryError>, forGenre genre: String) {
        genreStationsResultsByGenre[genre] = result
    }

    /// Lookups for `genre` wait until ``releaseGenreStations(forGenre:)``.
    func holdGenreStations(forGenre genre: String) {
        heldGenres.insert(genre)
    }

    func releaseGenreStations(forGenre genre: String) {
        heldGenres.remove(genre)
        for waiter in genreWaiters.removeValue(forKey: genre) ?? [] {
            waiter.resume()
        }
    }

    func genres() async throws(RadioDirectoryError) -> [Genre] {
        genresCallCount += 1
        switch genresResult {
        case let .success(genres): return genres
        case let .failure(error): throw error
        }
    }

    func topStations(limit _: Int) async throws(RadioDirectoryError) -> [Station] {
        topStationsCallCount += 1
        switch topStationsResult {
        case let .success(stations): return stations
        case let .failure(error): throw error
        }
    }

    func searchStations(matching _: String, limit _: Int) async throws(RadioDirectoryError) -> [Station] {
        switch searchStationsResult {
        case let .success(stations): stations
        case let .failure(error): throw error
        }
    }

    func stations(inGenre genre: String, limit _: Int) async throws(RadioDirectoryError) -> [Station] {
        genreStationsCallCount += 1
        if heldGenres.contains(genre) {
            await withCheckedContinuation { genreWaiters[genre, default: []].append($0) }
        }
        switch genreStationsResultsByGenre[genre] ?? .success([]) {
        case let .success(stations): return stations
        case let .failure(error): throw error
        }
    }

    func streamEndpoint(for _: Station) async throws(RadioDirectoryError) -> StreamEndpoint {
        throw .invalidResponse
    }
}

extension Station {
    static func fixture(id: String, name: String, genre: String = "Test", listenerCount: Int = 0) -> Station {
        Station(id: id, name: name, genre: genre, listenerCount: listenerCount)
    }
}
