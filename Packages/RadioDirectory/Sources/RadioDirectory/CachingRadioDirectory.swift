import Foundation

/// Decorator that caches the two discovery calls every landing surface makes
/// (`genres()` and `topStations(limit:)`) with a short TTL, and coalesces
/// concurrent requests into a single base fetch — Listen Now and Browse both
/// refresh at launch, and without this the directory is hit twice for identical
/// data (which also matters for Radio-Browser etiquette).
///
/// Successful fetches are also written to a ``DirectorySnapshotStoring`` so the
/// content survives process death. That persisted copy is deliberately *not*
/// served from `genres()`/`topStations(limit:)` — those stay "what the directory
/// says now", and callers that want the saved copy ask for it explicitly through
/// ``DirectoryDiscoveryCaching``. Keeping the two apart is what lets a surface
/// know whether it's showing live or saved content.
///
/// Search, genre, and stream-endpoint calls are user-driven and distinct, so they
/// pass straight through. Failures are never cached; the next call retries.
public actor CachingRadioDirectory: RadioDirectoryProviding, DirectoryDiscoveryCaching {
    /// Six hours: long enough that opening the app repeatedly in a day shows the
    /// same, instantly-painted list instead of a reshuffled one (top-click
    /// rankings drift constantly), short enough that a day's browsing isn't
    /// spent on yesterday's directory. Pull-to-refresh and the 4-hourly
    /// background refresh both bypass it.
    public static let defaultSnapshotTimeToLive: TimeInterval = 6 * 60 * 60

    private let base: any RadioDirectoryProviding
    private let timeToLive: TimeInterval
    /// Injected clock so TTL expiry is testable.
    private let now: @Sendable () -> Date

    private let snapshotStore: (any DirectorySnapshotStoring)?
    private let snapshotTimeToLive: TimeInterval
    /// Evaluated per snapshot read/write rather than captured once: the geo
    /// filter it describes changes at runtime.
    private let snapshotIdentity: @Sendable () async -> String?

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

    /// Mirrors what's on disk. Read once per process (the disk read is coalesced
    /// through `snapshotLoad`), then kept in step by every persisted write.
    private var persistedSnapshot: DirectoryDiscoverySnapshot?
    private var didLoadPersistedSnapshot = false
    private var snapshotLoad: Task<DirectoryDiscoverySnapshot?, Never>?

    public init(
        base: any RadioDirectoryProviding,
        timeToLive: TimeInterval = 60,
        snapshotStore: (any DirectorySnapshotStoring)? = nil,
        snapshotTimeToLive: TimeInterval = CachingRadioDirectory.defaultSnapshotTimeToLive,
        snapshotIdentity: @escaping @Sendable () async -> String? = { nil },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.base = base
        self.timeToLive = timeToLive
        self.snapshotStore = snapshotStore
        self.snapshotTimeToLive = snapshotTimeToLive
        self.snapshotIdentity = snapshotIdentity
        self.now = now
    }

    // MARK: - Cached discovery calls

    public func genres() async throws(RadioDirectoryError) -> [Genre] {
        if let cache = genresCache, isFresh(cache.fetchedAt) {
            return cache.value
        }

        if let inFlight = genresInFlight {
            // Coalescing intentionally awaits the shared unstructured task to
            // completion; cancelling one caller does not cancel the base fetch.
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
            await persist(genres: genres)
        }
        return try result.get()
    }

    public func topStations(limit: Int) async throws(RadioDirectoryError) -> [Station] {
        // A larger cached fetch can serve any smaller request.
        if let cache = topStationsCache, cache.fetchedLimit >= limit, isFresh(cache.fetchedAt) {
            return Array(cache.value.prefix(limit))
        }

        if let inFlight = topStationsInFlight, inFlight.limit >= limit {
            // Coalescing intentionally awaits the shared unstructured task to
            // completion; cancelling one caller does not cancel the base fetch.
            let stations = try (await inFlight.task.value).get()
            return Array(stations.prefix(limit))
        }

        let result = await fetchTopStations(limit: limit)

        if case let .success(stations) = result {
            // Don't let a slower, smaller fetch downgrade a fresher, larger
            // cache entry a concurrent caller already stored.
            let keepExisting = topStationsCache.map { isFresh($0.fetchedAt) && $0.fetchedLimit > limit } ?? false
            if !keepExisting {
                topStationsCache = TopStationsCache(value: stations, fetchedLimit: limit, fetchedAt: now())
                await persist(topStations: stations, limit: limit)
            }
        }
        return try Array(result.get().prefix(limit))
    }

    /// Issues the base top-stations fetch, registering it so concurrent callers
    /// can coalesce onto it. Extracted from `topStations(limit:)` so the cache
    /// bookkeeping there stays readable.
    private func fetchTopStations(limit: Int) async -> Result<[Station], RadioDirectoryError> {
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
        return result
    }

    // MARK: - Persisted snapshot

    public func discoverySnapshotState() async -> DirectoryDiscoverySnapshotState? {
        guard let snapshot = await loadPersistedSnapshot() else { return nil }
        guard let capturedAt = snapshot.capturedAt else { return nil }
        return DirectoryDiscoverySnapshotState(
            snapshot: snapshot,
            isFresh: now().timeIntervalSince(capturedAt) < snapshotTimeToLive
        )
    }

    public func invalidateMemoryCache() async {
        genresCache = nil
        topStationsCache = nil
    }

    /// Reads the stored snapshot once per process, coalescing concurrent first
    /// callers onto one file read, and discards a snapshot captured under a
    /// different source identity (another directory, or another geo filter).
    private func loadPersistedSnapshot() async -> DirectoryDiscoverySnapshot? {
        if didLoadPersistedSnapshot {
            return persistedSnapshot
        }

        if let snapshotLoad {
            return await snapshotLoad.value
        }

        guard let snapshotStore else {
            didLoadPersistedSnapshot = true
            return nil
        }

        let snapshotIdentity = self.snapshotIdentity
        let task = Task<DirectoryDiscoverySnapshot?, Never> {
            guard let stored = await snapshotStore.load() else { return nil }
            guard await snapshotIdentity() == stored.sourceIdentity else { return nil }
            return stored
        }

        snapshotLoad = task
        let snapshot = await task.value
        snapshotLoad = nil
        didLoadPersistedSnapshot = true
        persistedSnapshot = snapshot
        return snapshot
    }

    /// Rewrites the stored snapshot with one freshly fetched half, carrying the
    /// other half forward untouched — the two are fetched independently, and a
    /// genres-only refresh must not drop the saved stations (or backdate them).
    private func persist(
        topStations: [Station]? = nil,
        limit: Int? = nil,
        genres: [Genre]? = nil
    ) async {
        guard let snapshotStore else { return }

        // Both awaits are taken *before* the merge. The actor can admit another
        // `persist` while they're suspended (genres and top stations are fetched
        // concurrently), and merging against a snapshot read before that point
        // would drop the half the other write just added.
        _ = await loadPersistedSnapshot()
        let sourceIdentity = await snapshotIdentity()

        let capturedAt = now()
        let existing = persistedSnapshot
        let snapshot = DirectoryDiscoverySnapshot(
            topStations: topStations.map {
                DirectoryDiscoverySnapshot.TopStations(
                    stations: $0,
                    limit: limit ?? $0.count,
                    capturedAt: capturedAt
                )
            } ?? existing?.topStations,
            genres: genres.map {
                DirectoryDiscoverySnapshot.Genres(genres: $0, capturedAt: capturedAt)
            } ?? existing?.genres,
            sourceIdentity: sourceIdentity
        )

        // In-memory truth is updated synchronously with the merge; the file write
        // follows. If two concurrent writes race to the file the loser only costs
        // the on-disk copy one half until the next successful fetch rewrites it.
        persistedSnapshot = snapshot
        await snapshotStore.save(snapshot)
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
