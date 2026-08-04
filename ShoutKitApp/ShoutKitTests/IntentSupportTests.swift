import Foundation
import RadioDirectory
import Testing
@testable import ShoutKit

/// Unit coverage for the pure logic backing the Siri/Shortcuts intents — the
/// parts that don't need the App Intents runtime or the app's dependency graph.
/// The App Intents framework itself is exercised through real system pathways in
/// `AppIntentsPathwayTests`.
@Suite struct IntentSupportTests {
    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "IntentSupportTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeStation(
        id: String = "station-1",
        name: String = "KEXP",
        genre: String = "Alternative",
        artwork: String? = "https://example.com/art.png",
        stream: String? = "https://example.com/stream"
    ) -> Station {
        Station(
            id: id,
            name: name,
            genre: genre,
            listenerCount: 0,
            artworkURL: artwork.flatMap(URL.init(string:)),
            preferredStreamURL: stream.flatMap(URL.init(string:))
        )
    }

    // MARK: - StationEntity round-trip

    @Test func stationEntityCarriesTheFieldsSiriNeeds() {
        let entity = StationEntity(station: makeStation())

        #expect(entity.id == "station-1")
        #expect(entity.name == "KEXP")
        #expect(entity.genre == "Alternative")
        // `title` is the schema's canonical display name; `providerName` is
        // deliberately unset (ShoutKit doesn't track a broadcaster separately).
        #expect(entity.title == "KEXP")
        #expect(entity.providerName == nil)
    }

    @Test func stationEntityRoundTripsBackToAPlayableStation() {
        let original = makeStation()
        let restored = StationEntity(station: original).station

        #expect(restored.id == original.id)
        #expect(restored.name == original.name)
        #expect(restored.genre == original.genre)
        #expect(restored.artworkURL == original.artworkURL)
        #expect(restored.preferredStreamURL == original.preferredStreamURL)
    }

    @Test func stationEntityToleratesMissingURLs() {
        let entity = StationEntity(station: makeStation(artwork: nil, stream: nil))
        let restored = entity.station

        #expect(restored.artworkURL == nil)
        #expect(restored.preferredStreamURL == nil)
    }

    // MARK: - Schema enums

    @Test func playbackAttributesExposeEveryCaseToTheSchema() {
        #expect(PlaybackAttributes.caseDisplayRepresentations.count == 3)
        #expect(PlaybackAttributes.caseDisplayRepresentations[.none] != nil)
    }

    @Test func queueInsertionLocationsExposeEveryCaseToTheSchema() {
        #expect(QueueInsertionLocation.caseDisplayRepresentations.count == 3)
        #expect(QueueInsertionLocation.caseDisplayRepresentations[.now] != nil)
    }

    // MARK: - IntentStationCache

    // These cases guard the regression in #116: `StationEntity` used to be the
    // persisted type, and because the `@AppEntity(schema:)` macro's synthesized
    // property storage didn't survive a `Codable` round-trip, decoding one
    // trapped in `EntityProperty` — on the launch path, once the cache had been
    // written. The cache now persists a plain `CachedStation` snapshot instead,
    // so anything here that reads an entity back out of `UserDefaults` is
    // exercising that boundary. Each case gets its own defaults suite: they ran
    // against `UserDefaults.standard` in parallel before, which made them
    // interdependent.
    @Test func intentCacheKeepsNewestFirstAndDeduplicates() throws {
        let defaults = try makeDefaults()
        // Remembered entries are prepended, so the batch we just added is at the
        // front regardless of what was already in this cache.
        let batch = (0..<3).map { StationEntity(station: makeStation(id: "fresh-\($0)", name: "S\($0)")) }
        IntentStationCache.remember(batch, defaults: defaults)

        let loaded = IntentStationCache.load(defaults: defaults)
        #expect(loaded.prefix(3).map(\.id) == ["fresh-0", "fresh-1", "fresh-2"])

        // Re-remembering an existing id must not create a duplicate.
        IntentStationCache.remember([batch[0]], defaults: defaults)
        #expect(
            IntentStationCache.load(defaults: defaults).filter { $0.id == "fresh-0" }.count == 1
        )
    }

    @Test func intentCacheIsBoundedToItsCapacity() throws {
        let defaults = try makeDefaults()
        let many = (0..<80).map { StationEntity(station: makeStation(id: "cap-\($0)")) }
        IntentStationCache.remember(many, defaults: defaults)

        // Capacity is 50; the cache never grows unbounded no matter how many
        // stations a session hands it.
        #expect(IntentStationCache.load(defaults: defaults).count <= 50)
    }

    @Test func intentCacheLoadsPersistedStationSnapshots() throws {
        let defaults = try makeDefaults()
        let cachedJSON = """
        [
          {
            "id": "cached-1",
            "name": "Cached FM",
            "genre": "Eclectic",
            "artworkURLString": "https://example.com/cached.png",
            "streamURLString": "https://example.com/cached"
          }
        ]
        """
        defaults.set(Data(cachedJSON.utf8), forKey: "intents.station.cache")

        let loaded = try #require(IntentStationCache.load(defaults: defaults).first)

        #expect(loaded.id == "cached-1")
        #expect(loaded.title == "Cached FM")
        #expect(loaded.station.preferredStreamURL == URL(string: "https://example.com/cached"))
    }
}
