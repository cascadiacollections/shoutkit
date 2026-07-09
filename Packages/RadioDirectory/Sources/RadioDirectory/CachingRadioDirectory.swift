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

    /// A cached top-stations fetch, retained with the limit it was fetched at so
    /// a larger fetch can serve any smaller request.
    private struct TopStationsCache {
        let value: [Station]
        let fetchedLimit: Int
        let fetchedAt: Date
    }

    private var topStationsCache: TopStationsCache?
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
        // A concurrent larger request may have replaced our registration;
        // only clear the in-flight slot if it is still ours.
        if topStationsInFlight?.limit == limit {
            topStationsInFlight = nil
        }

        if case let .success(stations) = result {
            // Don't let a smaller fetch that finished late clobber a fresh,
            // larger cache written by a concurrent request.
            let keepExisting = topStationsCache.map { $0.fetchedLimit > limit && isFresh($0.fetchedAt) } ?? false
            if keepExisting == false {
                topStationsCache = TopStationsCache(value: stations, fetchedLimit: limit, fetchedAt: now())
            }
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
