import Foundation
@testable import Persistence
import SwiftData
import Testing

@MainActor
struct LibraryStoreDeduplicationTests {
    let container = ShoutKitModelContainer.makeContainer(inMemory: true)

    @Test func `two favorites for one station can be saved since version 2`() throws {
        let context = ModelContext(container)
        context.insert(FavoriteStation(stationID: "kexp", name: "KEXP", genre: "Eclectic"))
        context.insert(FavoriteStation(stationID: "kexp", name: "KEXP", genre: "Eclectic"))
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<FavoriteStation>()) == 2)
    }

    @Test func `creating the store keeps the favorite highest in the list`() throws {
        let context = ModelContext(container)
        let early = Date(timeIntervalSince1970: 1000)
        let late = Date(timeIntervalSince1970: 2000)
        context.insert(FavoriteStation(stationID: "kexp", name: "Lower", genre: "", createdAt: early, sortIndex: 4))
        context.insert(FavoriteStation(stationID: "kexp", name: "Top", genre: "", createdAt: early, sortIndex: 1))
        context.insert(FavoriteStation(stationID: "kexp", name: "Newer", genre: "", createdAt: late, sortIndex: 1))
        context.insert(FavoriteStation(stationID: "wfmu", name: "WFMU", genre: "", createdAt: early, sortIndex: 2))
        try context.save()

        let store = LibraryStore(context: context)

        let favorites = store.orderedFavorites()
        #expect(favorites.map(\.name) == ["Top", "WFMU"])
        #expect(store.favoriteIDs == ["kexp", "wfmu"])
    }

    @Test func `duplicate recents merge into the latest play with the counts added`() throws {
        let context = ModelContext(container)
        let older = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)
        context.insert(RecentStation(stationID: "kexp", name: "Phone", genre: "", playedAt: older, playCount: 3))
        context.insert(RecentStation(stationID: "kexp", name: "Watch", genre: "", playedAt: newer, playCount: 2))
        context.insert(RecentStation(stationID: "wfmu", name: "WFMU", genre: "", playedAt: older, playCount: 5))
        try context.save()

        let store = LibraryStore(context: context)

        let recents = try context.fetch(
            FetchDescriptor<RecentStation>(sortBy: [SortDescriptor(\.playedAt, order: .reverse)]),
        )
        #expect(recents.map(\.name) == ["Watch", "WFMU"])
        #expect(recents.map(\.playCount) == [5, 5])
        #expect(store.mergeDuplicateStations() == 0)
    }

    @Test func `merging reports how many rows it removed`() throws {
        let context = ModelContext(container)
        let store = LibraryStore(context: context)
        context.insert(FavoriteStation(stationID: "kexp", name: "A", genre: "", sortIndex: 0))
        context.insert(FavoriteStation(stationID: "kexp", name: "B", genre: "", sortIndex: 1))
        context.insert(RecentStation(stationID: "kexp", name: "A", genre: ""))
        context.insert(RecentStation(stationID: "kexp", name: "B", genre: ""))
        try context.save()

        #expect(store.mergeDuplicateStations() == 2)
        #expect(try context.fetchCount(FetchDescriptor<FavoriteStation>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<RecentStation>()) == 1)
    }
}
