import Foundation
import os
@testable import RadioDirectory
import Testing

/// In-memory `DirectorySnapshotStoring` that records what was written and can be
/// seeded with content, standing in for a previous launch.
private actor InMemorySnapshotStore: DirectorySnapshotStoring {
    private(set) var saved: DirectoryDiscoverySnapshot?
    private(set) var saveCount = 0
    private(set) var loadCount = 0

    init(seeded: DirectoryDiscoverySnapshot? = nil) {
        saved = seeded
    }

    func load() async -> DirectoryDiscoverySnapshot? {
        loadCount += 1
        return saved
    }

    func save(_ snapshot: DirectoryDiscoverySnapshot) async {
        saved = snapshot
        saveCount += 1
    }
}

private let referenceDate = Date(timeIntervalSinceReferenceDate: 0)

private func seededSnapshot(
    stationCount: Int = 5,
    limit: Int = 24,
    capturedAt: Date = referenceDate,
    sourceIdentity: String? = "test",
) -> DirectoryDiscoverySnapshot {
    DirectoryDiscoverySnapshot(
        topStations: DirectoryDiscoverySnapshot.TopStations(
            stations: (0 ..< stationCount).map {
                Station(id: "saved\($0)", name: "Saved \($0)", genre: "Test", listenerCount: 0)
            },
            limit: limit,
            capturedAt: capturedAt,
        ),
        genres: DirectoryDiscoverySnapshot.Genres(genres: [Genre(name: "Test")], capturedAt: capturedAt),
        sourceIdentity: sourceIdentity,
    )
}

struct CachingRadioDirectorySnapshotTests {
    @Test func `successful top stations fetch is persisted`() async throws {
        let store = InMemorySnapshotStore()
        let cache = CachingRadioDirectory(
            base: CountingDirectory(),
            snapshotStore: store,
            snapshotIdentity: { "radio-browser;country=US" },
        )

        _ = try await cache.topStations(limit: 24)

        let saved = await store.saved
        #expect(saved?.topStations?.stations.count == 24)
        #expect(saved?.topStations?.limit == 24)
        #expect(saved?.sourceIdentity == "radio-browser;country=US")
    }

    @Test func `genres fetch does not drop saved stations`() async throws {
        let store = InMemorySnapshotStore()
        let cache = CachingRadioDirectory(base: CountingDirectory(), snapshotStore: store)

        _ = try await cache.topStations(limit: 24)
        _ = try await cache.genres()

        let saved = await store.saved
        // Each half is fetched independently; persisting one must carry the other
        // forward rather than replacing the whole snapshot.
        #expect(saved?.topStations?.stations.count == 24)
        #expect(saved?.genres?.genres.isEmpty == false)
    }

    @Test func `failed fetch is not persisted`() async throws {
        let counting = CountingDirectory()
        await counting.setFailNextTopStations(true)
        let store = InMemorySnapshotStore()
        let cache = CachingRadioDirectory(base: counting, snapshotStore: store)

        await #expect(throws: RadioDirectoryError.transport("offline")) {
            _ = try await cache.topStations(limit: 24)
        }

        #expect(await store.saveCount == 0)
    }

    @Test func `saved snapshot is fresh inside its window`() async {
        let cache = CachingRadioDirectory(
            base: CountingDirectory(),
            snapshotStore: InMemorySnapshotStore(seeded: seededSnapshot()),
            snapshotTimeToLive: 60,
            snapshotIdentity: { "test" },
            now: { referenceDate.addingTimeInterval(59) },
        )

        let state = await cache.discoverySnapshotState()

        #expect(state?.isFresh == true)
        #expect(state?.snapshot.topStations?.stations.count == 5)
        #expect(state?.snapshot.capturedAt == referenceDate)
    }

    @Test func `saved snapshot outside its window is still returned but not fresh`() async {
        let cache = CachingRadioDirectory(
            base: CountingDirectory(),
            snapshotStore: InMemorySnapshotStore(seeded: seededSnapshot()),
            snapshotTimeToLive: 60,
            snapshotIdentity: { "test" },
            now: { referenceDate.addingTimeInterval(61) },
        )

        let state = await cache.discoverySnapshotState()

        // Still handed back: a surface would rather paint stale stations than a
        // spinner. It just isn't allowed to skip the refresh.
        #expect(state?.isFresh == false)
        #expect(state?.snapshot.topStations?.stations.count == 5)
    }

    @Test func `snapshot captured under another source identity is ignored`() async {
        let cache = CachingRadioDirectory(
            base: CountingDirectory(),
            snapshotStore: InMemorySnapshotStore(seeded: seededSnapshot(sourceIdentity: "country=US")),
            snapshotIdentity: { "country=JP" },
            now: { referenceDate },
        )

        #expect(await cache.discoverySnapshotState() == nil)
    }

    @Test func `snapshot stops being served when the identity changes mid session`() async {
        let identity = OSAllocatedUnfairLock(initialState: "country=US")
        let cache = CachingRadioDirectory(
            base: CountingDirectory(),
            snapshotStore: InMemorySnapshotStore(seeded: seededSnapshot(sourceIdentity: "country=US")),
            snapshotIdentity: { identity.withLock { $0 } },
            now: { referenceDate },
        )

        #expect(await cache.discoverySnapshotState() != nil)
        identity.withLock { $0 = "country=JP" }

        // Travel, or the geo flag being toggled, has to take effect immediately —
        // the identity is checked per read, not once when the file was loaded.
        #expect(await cache.discoverySnapshotState() == nil)
    }

    @Test func `persisted halves are not carried across an identity change`() async throws {
        let identity = OSAllocatedUnfairLock(initialState: "country=US")
        let store = InMemorySnapshotStore(seeded: seededSnapshot(sourceIdentity: "country=US"))
        let cache = CachingRadioDirectory(
            base: CountingDirectory(),
            snapshotStore: store,
            snapshotIdentity: { identity.withLock { $0 } },
            now: { referenceDate },
        )

        _ = await cache.discoverySnapshotState()
        identity.withLock { $0 = "country=JP" }
        _ = try await cache.genres()

        let saved = await store.saved
        // A genres fetch must not launder the previous region's stations into a
        // snapshot stamped with the new identity.
        #expect(saved?.sourceIdentity == "country=JP")
        #expect(saved?.topStations == nil)
        #expect(saved?.genres?.genres.isEmpty == false)
    }

    @Test func `snapshot is read from disk only once`() async {
        let store = InMemorySnapshotStore(seeded: seededSnapshot())
        let cache = CachingRadioDirectory(
            base: CountingDirectory(),
            snapshotStore: store,
            snapshotIdentity: { "test" },
            now: { referenceDate },
        )

        _ = await cache.discoverySnapshotState()
        _ = await cache.discoverySnapshotState()

        #expect(await store.loadCount == 1)
    }

    @Test func `concurrent first reads share one disk load`() async {
        let store = InMemorySnapshotStore(seeded: seededSnapshot())
        let cache = CachingRadioDirectory(
            base: CountingDirectory(),
            snapshotStore: store,
            snapshotIdentity: { "test" },
            now: { referenceDate },
        )

        let first = Task { await cache.discoverySnapshotState() }
        let second = Task { await cache.discoverySnapshotState() }
        _ = await first.value
        _ = await second.value

        #expect(await store.loadCount == 1)
    }

    @Test func `discovery snapshot state is nil without A store`() async {
        let cache = CachingRadioDirectory(base: CountingDirectory())

        #expect(await cache.discoverySnapshotState() == nil)
    }

    @Test func `invalidate memory cache sends the next read to the directory`() async throws {
        let counting = CountingDirectory()
        let cache = CachingRadioDirectory(base: counting)

        _ = try await cache.topStations(limit: 24)
        _ = try await cache.genres()
        await cache.invalidateMemoryCache()
        _ = try await cache.topStations(limit: 24)
        _ = try await cache.genres()

        // Pull-to-refresh has to actually refresh, even inside the short window.
        #expect(await counting.topStationsCalls == 2)
        #expect(await counting.genresCalls == 2)
    }

    @Test func `saved content is not served from the live discovery calls`() async throws {
        let counting = CountingDirectory()
        let cache = CachingRadioDirectory(
            base: counting,
            snapshotStore: InMemorySnapshotStore(seeded: seededSnapshot()),
            snapshotIdentity: { "test" },
            now: { referenceDate },
        )

        let stations = try await cache.topStations(limit: 24)

        // `topStations` means "what the directory says now" — the persisted copy
        // is only reachable through `discoverySnapshotState()`, so a surface can
        // always tell live content from saved.
        #expect(stations.first?.id == "s0")
        #expect(await counting.topStationsCalls == 1)
    }
}

struct FileDirectorySnapshotStoreTests {
    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ShoutKitSnapshotTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("DiscoverySnapshot.v1.json", isDirectory: false)
    }

    @Test func `snapshot round trips through the file`() async {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = FileDirectorySnapshotStore(fileURL: fileURL)
        let snapshot = seededSnapshot(stationCount: 3, sourceIdentity: "radio-browser;country=US")

        await store.save(snapshot)
        let loaded = await store.load()

        #expect(loaded == snapshot)
    }

    @Test func `missing file loads as no snapshot`() async {
        let store = FileDirectorySnapshotStore(fileURL: temporaryFileURL())

        #expect(await store.load() == nil)
    }

    @Test func `corrupt file loads as no snapshot`() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("not json".utf8).write(to: fileURL)
        let store = FileDirectorySnapshotStore(fileURL: fileURL)

        // A truncated or stale-shaped file is the same as having none: refetch.
        #expect(await store.load() == nil)
    }

    @Test func `empty snapshot loads as no snapshot`() async {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = FileDirectorySnapshotStore(fileURL: fileURL)

        await store.save(DirectoryDiscoverySnapshot(sourceIdentity: "test"))

        // Otherwise an empty snapshot would suppress the first real fetch.
        #expect(await store.load() == nil)
    }
}
