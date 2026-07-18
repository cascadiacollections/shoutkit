import Foundation
import RadioDirectory
import Testing
@testable import ShoutKit

/// Unit coverage for the pure logic backing the Siri/Shortcuts intents — the
/// parts that don't need the App Intents runtime or the app's dependency graph.
/// The App Intents framework itself is exercised through real system pathways in
/// `AppIntentsPathwayTests`.
@Suite struct IntentSupportTests {
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

    @Test func intentCacheKeepsNewestFirstAndDeduplicates() {
        // Remembered entries are prepended, so the batch we just added is at the
        // front regardless of what earlier runs left in `UserDefaults.standard`.
        let batch = (0..<3).map { StationEntity(station: makeStation(id: "fresh-\($0)", name: "S\($0)")) }
        IntentStationCache.remember(batch)

        let loaded = IntentStationCache.load()
        #expect(loaded.prefix(3).map(\.id) == ["fresh-0", "fresh-1", "fresh-2"])

        // Re-remembering an existing id must not create a duplicate.
        IntentStationCache.remember([batch[0]])
        #expect(IntentStationCache.load().filter { $0.id == "fresh-0" }.count == 1)
    }

    @Test func intentCacheIsBoundedToItsCapacity() {
        let many = (0..<80).map { StationEntity(station: makeStation(id: "cap-\($0)")) }
        IntentStationCache.remember(many)

        // Capacity is 50; the cache never grows unbounded no matter how many
        // stations a session hands it.
        #expect(IntentStationCache.load().count <= 50)
    }
}
