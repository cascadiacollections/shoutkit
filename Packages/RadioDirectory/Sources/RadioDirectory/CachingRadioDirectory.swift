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
    /// An in-flight top-stations base fetch and the limit it was issued with.
    /// The generation distinguishes concurrent mixed-limit fetches: a
    /// larger-limit request replaces a smaller in-flight registration, and the
    /// smaller fetch must not deregister (or cache over) the newer one when it
    /// completes.
    private struct TopStationsInFlight {
        let task: Task<Result<[Station], RadioDirectoryError>, Never>
        let limit: Int
        let generation: Int
    }

    private var topStationsInFlight: TopStationsInFlight?
    private var topStationsGeneration = 0

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

        topStationsGeneration += 1
        let generation = topStationsGeneration
        topStationsInFlight = TopStationsInFlight(task: task, limit: limit, generation: generation)
        let result = await task.value
        // Only deregister our own registration — a concurrent larger-limit
        // fetch may have replaced it while we awaited.
        if topStationsInFlight?.generation == generation {
            topStationsInFlight = nil
        }

        if case let .success(stations) = result {
            // Don't let a slower, smaller fetch downgrade a fresher, larger
            // cache entry a concurrent caller already stored.
            let keepExisting = topStationsCache.map { isFresh($0.fetchedAt) && $0.fetchedLimit > limit } ?? false
            if !keepExisting {
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

    public func station(id: String) async throws(RadioDirectoryError) -> Station? {
        try await base.station(id: id)
    }

    public func streamEndpoint(for station: Station) async throws(RadioDirectoryError) -> StreamEndpoint {
        try await base.streamEndpoint(for: station)
    }

    // MARK: - Helpers

    private func isFresh(_ fetchedAt: Date) -> Bool {
        now().timeIntervalSince(fetchedAt) < timeToLive
    }
}
