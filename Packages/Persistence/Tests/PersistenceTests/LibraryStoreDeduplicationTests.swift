import CoreData
import Foundation
@testable import Persistence
import RadioDirectory
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

    @Test func `logging a play collapses duplicate recents into the latest row`() throws {
        let context = ModelContext(container)
        let store = LibraryStore(context: context)
        // Arrive after the store merged at creation, as a sync import would.
        context.insert(RecentStation(
            stationID: "kexp", name: "Older", genre: "", playedAt: Date(timeIntervalSince1970: 1000), playCount: 3,
        ))
        context.insert(RecentStation(
            stationID: "kexp", name: "Newer", genre: "", playedAt: Date(timeIntervalSince1970: 2000), playCount: 2,
        ))
        try context.save()

        store.logRecent(Station(id: "kexp", name: "KEXP", genre: "Eclectic", listenerCount: 0))

        let recents = try context.fetch(FetchDescriptor<RecentStation>())
        #expect(recents.count == 1)
        #expect(recents.first?.name == "KEXP")
        #expect(recents.first?.playCount == 6)
    }

    @Test func `recents keyed by station keep the latest play`() {
        let older = RecentStation(stationID: "kexp", name: "Old", genre: "", playedAt: .init(timeIntervalSince1970: 1))
        let newer = RecentStation(stationID: "kexp", name: "New", genre: "", playedAt: .init(timeIntervalSince1970: 2))
        let other = RecentStation(stationID: "wfmu", name: "WFMU", genre: "")

        for order in [[older, newer, other], [newer, other, older]] {
            let byID = RecentStation.latestByStationID(order)
            #expect(byID.count == 2)
            #expect(byID["kexp"]?.name == "New")
            #expect(byID["wfmu"]?.name == "WFMU")
        }
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

    @Test func `reconciling after a remote change picks up favorites it did not insert`() throws {
        let context = ModelContext(container)
        let store = LibraryStore(context: context)
        #expect(store.favoriteIDs.isEmpty)

        // What an import from another device looks like to the store: rows it
        // never inserted, one of them a duplicate.
        context.insert(FavoriteStation(stationID: "kexp", name: "KEXP", genre: "", sortIndex: 0))
        context.insert(FavoriteStation(stationID: "kexp", name: "KEXP", genre: "", sortIndex: 1))
        context.insert(FavoriteStation(stationID: "wfmu", name: "WFMU", genre: "", sortIndex: 2))
        try context.save()

        store.reconcileAfterRemoteChange()

        #expect(store.favoriteIDs == ["kexp", "wfmu"])
        #expect(try context.fetchCount(FetchDescriptor<FavoriteStation>()) == 2)
    }

    @Test func `a remote change notification reconciles the store`() async throws {
        let context = ModelContext(container)
        let store = LibraryStore(context: context)
        let center = NotificationCenter()
        let token = store.observeRemoteChanges(in: center)
        defer { center.removeObserver(token) }

        context.insert(FavoriteStation(stationID: "kexp", name: "KEXP", genre: ""))
        try context.save()
        center.post(name: .NSPersistentStoreRemoteChange, object: nil)

        // The observer runs on the main queue, which may be after this line.
        for _ in 0 ..< 200 where store.favoriteIDs.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.favoriteIDs == ["kexp"])
    }
}
