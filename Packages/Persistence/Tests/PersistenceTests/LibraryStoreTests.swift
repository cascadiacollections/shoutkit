import Foundation
import RadioDirectory
import SwiftData
import Testing

@testable import Persistence

@MainActor
struct LibraryStoreTests {
    private func makeStoreAndContext() -> (LibraryStore, ModelContext) {
        let container = ShoutKitModelContainer.makeContainer(inMemory: true)
        let context = ModelContext(container)
        return (LibraryStore(context: context), context)
    }

    private func station(_ id: String) -> Station {
        Station(id: id, name: "Station \(id)", genre: "Test", listenerCount: 10)
    }

    @Test func togglingFavoriteAddsThenRemoves() {
        let (store, _) = makeStoreAndContext()
        let station = station("a")

        #expect(store.isFavorite(station) == false)

        let added = store.toggleFavorite(station)
        #expect(added == true)
        #expect(store.isFavorite(station) == true)
        #expect(store.favoriteIDs.contains("a"))

        let stillFavorite = store.toggleFavorite(station)
        #expect(stillFavorite == false)
        #expect(store.isFavorite(station) == false)
    }

    @Test func loggingSameStationTwiceKeepsOneRecent() throws {
        let (store, context) = makeStoreAndContext()

        store.logRecent(station("a"))
        store.logRecent(station("a"))

        let recents = try context.fetch(FetchDescriptor<RecentStation>())
        #expect(recents.count == 1)
        #expect(recents.first?.stationID == "a")
    }

    @Test func recentsAreCappedAtLimit() throws {
        let (store, context) = makeStoreAndContext()

        for index in 0..<(LibraryStore.recentsLimit + 10) {
            store.logRecent(station("s\(index)"))
        }

        let count = try context.fetch(FetchDescriptor<RecentStation>()).count
        #expect(count <= LibraryStore.recentsLimit)
    }

    @Test func recentsEvictionKeepsNewestEntries() throws {
        let (store, context) = makeStoreAndContext()
        let overflow = 5
        let total = LibraryStore.recentsLimit + overflow

        for index in 0..<total {
            store.logRecent(station("s\(index)"))
        }

        let descriptor = FetchDescriptor<RecentStation>(
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
        )
        let recents = try context.fetch(descriptor)
        let keptIDs = Set(recents.map(\.stationID))

        // The most recently played stations survive; the oldest are evicted.
        for index in overflow..<total {
            #expect(keptIDs.contains("s\(index)"), "expected s\(index) to be kept")
        }
        for index in 0..<overflow {
            #expect(keptIDs.contains("s\(index)") == false, "expected s\(index) to be evicted")
        }
    }
}
