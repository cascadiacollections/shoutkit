import Clocks
import ConcurrencyExtras
import Foundation
import os
@testable import RadioDirectory
import Testing

/// Base-directory fake that counts calls and can hold responses on a clock so
/// tests can land a second request while the first is still in flight.
actor CountingDirectory: RadioDirectoryProviding {
    private(set) var genresCalls = 0
    private(set) var topStationsCalls = 0
    private(set) var stationLookupCalls = 0

    var responseDelay: Duration = .zero
    private var responseClock: any Clock<Duration> = ContinuousClock()
    var failNextTopStations = false

    /// Calls made after this sleep `delay` on `clock` before answering. Pass a
    /// `TestClock` and the call stays in flight until the test advances it.
    func setResponseDelay(_ delay: Duration, on clock: any Clock<Duration>) {
        responseDelay = delay
        responseClock = clock
    }

    func setFailNextTopStations(_ fail: Bool) {
        failNextTopStations = fail
    }

    private let stations = (0 ..< 30).map { index in
        Station(id: Station.ID("s\(index)"), name: "Station \(index)", genre: "Test", listenerCount: 0)
    }

    func genres() async throws(RadioDirectoryError) -> [Genre] {
        genresCalls += 1
        try? await responseClock.sleep(for: responseDelay)
        return [Genre(name: "Test", stationCount: stations.count)]
    }

    func topStations(limit: Int) async throws(RadioDirectoryError) -> [Station] {
        topStationsCalls += 1
        try? await responseClock.sleep(for: responseDelay)
        if failNextTopStations {
            failNextTopStations = false
            throw RadioDirectoryError.transport("offline")
        }
        return Array(stations.prefix(limit))
    }

    func searchStations(matching _: String, limit _: Int) async throws(RadioDirectoryError) -> [Station] {
        []
    }

    func station(id: Station.ID) async throws(RadioDirectoryError) -> Station? {
        stationLookupCalls += 1
        return stations.first(where: { $0.id == id })
    }

    func streamEndpoint(for _: Station) async throws(RadioDirectoryError) -> StreamEndpoint {
        throw RadioDirectoryError.emptyPlaylist
    }
}

struct CachingRadioDirectoryTests {
    @Test func `second request within TTL serves from cache`() async throws {
        let counting = CountingDirectory()
        let cache = CachingRadioDirectory(base: counting)

        _ = try await cache.topStations(limit: 24)
        _ = try await cache.topStations(limit: 24)
        _ = try await cache.genres()
        _ = try await cache.genres()

        #expect(await counting.topStationsCalls == 1)
        #expect(await counting.genresCalls == 1)
    }

    @Test func `smaller limit is served from larger cached fetch`() async throws {
        let counting = CountingDirectory()
        let cache = CachingRadioDirectory(base: counting)

        _ = try await cache.topStations(limit: 24)
        let smaller = try await cache.topStations(limit: 10)

        #expect(smaller.count == 10)
        #expect(await counting.topStationsCalls == 1)
    }

    @Test func `larger limit bypasses smaller cached fetch`() async throws {
        let counting = CountingDirectory()
        let cache = CachingRadioDirectory(base: counting)

        _ = try await cache.topStations(limit: 10)
        let larger = try await cache.topStations(limit: 24)

        #expect(larger.count == 24)
        #expect(await counting.topStationsCalls == 2)
    }

    @Test func `memory cache serves until the injected clock passes the TTL`() async throws {
        let clock = TestClock()
        let counting = CountingDirectory()
        let cache = CachingRadioDirectory(base: counting, timeToLive: 60, clock: clock)

        _ = try await cache.topStations(limit: 24)
        _ = try await cache.genres()

        await clock.advance(by: .seconds(59))
        _ = try await cache.topStations(limit: 24)
        _ = try await cache.genres()
        #expect(await counting.topStationsCalls == 1)
        #expect(await counting.genresCalls == 1)

        await clock.advance(by: .seconds(2))
        _ = try await cache.topStations(limit: 24)
        _ = try await cache.genres()
        #expect(await counting.topStationsCalls == 2)
        #expect(await counting.genresCalls == 2)
    }

    @Test func `failures are not cached`() async throws {
        let counting = CountingDirectory()
        await counting.setFailNextTopStations(true)
        let cache = CachingRadioDirectory(base: counting)

        await #expect(throws: RadioDirectoryError.transport("offline")) {
            _ = try await cache.topStations(limit: 24)
        }

        // The failure must not be served from cache; the retry hits the base.
        let stations = try await cache.topStations(limit: 24)
        #expect(stations.count == 24)
        #expect(await counting.topStationsCalls == 2)
    }

    @Test func `memory cache is not served after the snapshot identity changes`() async throws {
        let identity = OSAllocatedUnfairLock(initialState: "country=US")
        let counting = CountingDirectory()
        let cache = CachingRadioDirectory(
            base: counting,
            snapshotIdentity: { identity.withLock { $0 } },
        )

        _ = try await cache.topStations(limit: 24)
        _ = try await cache.genres()
        identity.withLock { $0 = "country=JP" }
        _ = try await cache.topStations(limit: 24)
        _ = try await cache.genres()

        // Travel, or a region change, has to miss the 60-second window too.
        // The on-disk snapshot already did; the memory tier was still serving
        // the previous region's list.
        #expect(await counting.topStationsCalls == 2)
        #expect(await counting.genresCalls == 2)
    }

    @Test func `same snapshot identity still serves the memory cache`() async throws {
        let counting = CountingDirectory()
        let cache = CachingRadioDirectory(
            base: counting,
            snapshotIdentity: { "country=US" },
        )

        _ = try await cache.topStations(limit: 24)
        _ = try await cache.topStations(limit: 10)
        _ = try await cache.genres()
        _ = try await cache.genres()

        #expect(await counting.topStationsCalls == 1)
        #expect(await counting.genresCalls == 1)
    }

    @Test func `station lookup passes through to base`() async throws {
        let counting = CountingDirectory()
        let cache = CachingRadioDirectory(base: counting)

        let found = try await cache.station(id: "s0")
        let missing = try await cache.station(id: "missing")

        #expect(found?.name == "Station 0")
        #expect(missing == nil)
        #expect(await counting.stationLookupCalls == 2)
    }
}

/// Requests that must overlap. Each test runs under `withMainSerialExecutor`,
/// so every hop between the test, the cache actor, and the fake is enqueued on
/// one serial queue in a fixed order, and `Task.megaYield()` is enough to let
/// a request reach the fake and park on the `TestClock`. Before this, the first
/// request had 30 real milliseconds to get there and 150 to stay there.
///
/// `withMainSerialExecutor` swaps a process-wide runtime hook and restores the
/// previous value when it returns, so two overlapping calls can restore each
/// other's state. `.serialized` keeps these tests from overlapping, and this is
/// the only suite in the target that uses it (DECISIONS.md, 2026-11-28).
@MainActor
@Suite(.serialized)
struct CachingRadioDirectoryInFlightTests {
    private static let hold: Duration = .seconds(1)

    @Test func `concurrent top stations requests share one base fetch`() async throws {
        try await withMainSerialExecutor {
            let clock = TestClock()
            let counting = CountingDirectory()
            await counting.setResponseDelay(Self.hold, on: clock)
            let cache = CachingRadioDirectory(base: counting)

            let first = Task { try await cache.topStations(limit: 24) }
            await Task.megaYield()
            #expect(await counting.topStationsCalls == 1, "the first request is in flight")
            let second = Task { try await cache.topStations(limit: 24) }
            await Task.megaYield()

            await clock.advance(by: Self.hold)
            let firstStations = try await first.value
            let secondStations = try await second.value

            #expect(firstStations.count == 24)
            #expect(secondStations.count == 24)
            #expect(await counting.topStationsCalls == 1, "concurrent callers must share one base fetch")
        }
    }

    @Test func `an in flight fetch is not reused after the identity changes`() async throws {
        try await withMainSerialExecutor {
            let clock = TestClock()
            let identity = OSAllocatedUnfairLock(initialState: "country=US")
            let counting = CountingDirectory()
            let cache = CachingRadioDirectory(
                base: counting,
                snapshotIdentity: { identity.withLock { $0 } },
            )

            // The US fetch is held twice as long as the JP one, so it lands last.
            await counting.setResponseDelay(Self.hold * 2, on: clock)
            let first = Task { try await cache.topStations(limit: 24) }
            await Task.megaYield()
            identity.withLock { $0 = "country=JP" }
            await counting.setResponseDelay(Self.hold, on: clock)
            let second = Task { try await cache.topStations(limit: 24) }
            await Task.megaYield()
            #expect(await counting.topStationsCalls == 2)

            await clock.advance(by: Self.hold)
            _ = try await second.value
            await clock.advance(by: Self.hold)
            _ = try await first.value

            // The US result finishing late must not replace the JP cache entry.
            _ = try await cache.topStations(limit: 24)
            #expect(await counting.topStationsCalls == 2)
        }
    }
}
