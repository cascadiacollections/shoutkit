import Foundation

/// Decorator that caches the two discovery calls every landing surface makes
/// (`genres()` and `topStations(limit:)`) with a short TTL, and coalesces
/// concurrent requests into a single base fetch — Listen Now and Browse both
/// refresh at launch, and without this the directory is hit twice for identical
/// data (which also matters for Radio-Browser etiquette).
///
/// Search, genre, and stream-endpoint calls are user-driven and distinct, so they
/// pass straight through. Failures are never cached; the next call retries.
public actor CachingRadioDirectory: RadioDirectoryProviding {
    private let base: any RadioDirectoryProviding
    private let timeToLive: TimeInterval
    /// Injected clock so TTL expiry is testable.
    private let now: @Sendable () -> Date

    private var genresCache: (value: [Genre], fetchedAt: Date)?
    private var genresInFlight: Task<Result<[Genre], RadioDirectoryError>, Never>?

    private var topStationsCache: (value: [Station], fetchedLimit: Int, fetchedAt: Date)?
    private var topStationsInFlight: (task: Task<Result<[Station], RadioDirectoryError>, Never>, limit: Int)?

    public init(
        base: any RadioDirectoryProviding,
        timeToLive: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.base = base
        self.timeToLive = timeToLive
        self.now = now
    }

    // MARK: - Cached discovery calls

    public func genres() async throws(RadioDirectoryError) -> [Genre] {
        if let cache = genresCache, isFresh(cache.fetchedAt) {
            return cache.value
        }

        if let inFlight = genresInFlight {
            return try (await inFlight.value).get()
        }

        let base = self.base
        let task = Task<Result<[Genre], RadioDirectoryError>, Never> {
            do {
                return .success(try await base.genres())
            } catch let error as RadioDirectoryError {
                return .failure(error)
            } catch {
                return .failure(.transport(error.localizedDescription))
            }
        }

        genresInFlight = task
        let result = await task.value
        genresInFlight = nil

        if case let .success(genres) = result {
            genresCache = (genres, now())
        }
        return try result.get()
    }

    public func topStations(limit: Int) async throws(RadioDirectoryError) -> [Station] {
        // A larger cached fetch can serve any smaller request.
        if let cache = topStationsCache, cache.fetchedLimit >= limit, isFresh(cache.fetchedAt) {
            return Array(cache.value.prefix(limit))
        }

        if let inFlight = topStationsInFlight, inFlight.limit >= limit {
            let stations = try (await inFlight.task.value).get()
            return Array(stations.prefix(limit))
        }

        let base = self.base
        let task = Task<Result<[Station], RadioDirectoryError>, Never> {
            do {
                return .success(try await base.topStations(limit: limit))
            } catch let error as RadioDirectoryError {
                return .failure(error)
            } catch {
                return .failure(.transport(error.localizedDescription))
            }
        }

        topStationsInFlight = (task, limit)
        let result = await task.value
        topStationsInFlight = nil

        if case let .success(stations) = result {
            topStationsCache = (stations, limit, now())
        }
        return try Array(result.get().prefix(limit))
    }

    // MARK: - Pass-through calls

    public func searchStations(matching query: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        try await base.searchStations(matching: query, limit: limit)
    }

    public func stations(inGenre genre: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        try await base.stations(inGenre: genre, limit: limit)
    }

    public func streamEndpoint(for station: Station) async throws(RadioDirectoryError) -> StreamEndpoint {
        try await base.streamEndpoint(for: station)
    }

    // MARK: - Helpers

    private func isFresh(_ fetchedAt: Date) -> Bool {
        now().timeIntervalSince(fetchedAt) < timeToLive
    }
}
