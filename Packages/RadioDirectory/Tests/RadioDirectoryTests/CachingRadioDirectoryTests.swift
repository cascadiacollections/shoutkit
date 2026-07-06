import Foundation
import os
import Testing

@testable import RadioDirectory

/// Base-directory fake that counts calls and can delay responses so tests can
/// deterministically land a second request mid-flight.
actor CountingDirectory: RadioDirectoryProviding {
    private(set) var genresCalls = 0
    private(set) var topStationsCalls = 0

    var responseDelay: Duration = .zero
    var failNextTopStations = false

    func setResponseDelay(_ delay: Duration) { responseDelay = delay }
    func setFailNextTopStations(_ fail: Bool) { failNextTopStations = fail }

    private let stations = (0..<30).map { index in
        Station(id: "s\(index)", name: "Station \(index)", genre: "Test", listenerCount: 0)
    }

    func genres() async throws(RadioDirectoryError) -> [Genre] {
        genresCalls += 1
        try? await Task.sleep(for: responseDelay)
        return [Genre(name: "Test", stationCount: stations.count)]
    }

    func topStations(limit: Int) async throws(RadioDirectoryError) -> [Station] {
        topStationsCalls += 1
        try? await Task.sleep(for: responseDelay)
        if failNextTopStations {
            failNextTopStations = false
            throw RadioDirectoryError.transport("offline")
        }
        return Array(stations.prefix(limit))
    }

    func searchStations(matching query: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        []
    }

    func streamEndpoint(for station: Station) async throws(RadioDirectoryError) -> StreamEndpoint {
        throw RadioDirectoryError.emptyPlaylist
    }
}

struct CachingRadioDirectoryTests {
    @Test func concurrentTopStationsRequestsShareOneBaseFetch() async throws {
        let counting = CountingDirectory()
        await counting.setResponseDelay(.milliseconds(150))
        let cache = CachingRadioDirectory(base: counting)

        let first = Task { try await cache.topStations(limit: 24) }
        // Let the first call enter the actor and register as in-flight.
        try? await Task.sleep(for: .milliseconds(30))
        let second = Task { try await cache.topStations(limit: 24) }

        let firstStations = try await first.value
        let secondStations = try await second.value

        #expect(firstStations.count == 24)
        #expect(secondStations.count == 24)
        #expect(await counting.topStationsCalls == 1, "concurrent callers must share one base fetch")
    }

    @Test func secondRequestWithinTTLServesFromCache() async throws {
        let counting = CountingDirectory()
        let cache = CachingRadioDirectory(base: counting)

        _ = try await cache.topStations(limit: 24)
        _ = try await cache.topStations(limit: 24)
        _ = try await cache.genres()
        _ = try await cache.genres()

        #expect(await counting.topStationsCalls == 1)
        #expect(await counting.genresCalls == 1)
    }

    @Test func smallerLimitIsServedFromLargerCachedFetch() async throws {
        let counting = CountingDirectory()
        let cache = CachingRadioDirectory(base: counting)

        _ = try await cache.topStations(limit: 24)
        let smaller = try await cache.topStations(limit: 10)

        #expect(smaller.count == 10)
        #expect(await counting.topStationsCalls == 1)
    }

    @Test func largerLimitBypassesSmallerCachedFetch() async throws {
        let counting = CountingDirectory()
        let cache = CachingRadioDirectory(base: counting)

        _ = try await cache.topStations(limit: 10)
        let larger = try await cache.topStations(limit: 24)

        #expect(larger.count == 24)
        #expect(await counting.topStationsCalls == 2)
    }

    @Test func expiredTTLRefetches() async throws {
        let clock = OSAllocatedUnfairLock(initialState: Date(timeIntervalSinceReferenceDate: 0))
        let counting = CountingDirectory()
        let cache = CachingRadioDirectory(
            base: counting,
            timeToLive: 60,
            now: { clock.withLock { $0 } }
        )

        _ = try await cache.topStations(limit: 24)
        clock.withLock { $0 = $0.addingTimeInterval(61) }
        _ = try await cache.topStations(limit: 24)

        #expect(await counting.topStationsCalls == 2)
    }

    @Test func failuresAreNotCached() async throws {
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
}
