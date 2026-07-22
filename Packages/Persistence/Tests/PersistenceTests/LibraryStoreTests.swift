import Foundation
import RadioDirectory
import SwiftData
import Testing

@testable import Persistence

// Shared fixtures for both suites in this file.
@MainActor
private func makeStoreAndContext() -> (LibraryStore, ModelContext) {
    let container = ShoutKitModelContainer.makeContainer(inMemory: true)
    let context = ModelContext(container)
    return (LibraryStore(context: context), context)
}

private func station(_ id: String) -> Station {
    Station(id: id, name: "Station \(id)", genre: "Test", listenerCount: 10)
}

@MainActor
// swiftlint:disable:next type_body_length
struct LibraryStoreTests {
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

    // MARK: - Favorite ordering

    private func favoritesBySortIndex(_ context: ModelContext) throws -> [FavoriteStation] {
        // Break ties on `createdAt` so rows sharing a `sortIndex` (e.g. the
        // non-legacy duplicate case) read back in a deterministic order rather
        // than SwiftData's unspecified fetch order.
        try context.fetch(
            FetchDescriptor<FavoriteStation>(sortBy: [
                SortDescriptor(\.sortIndex, order: .forward),
                SortDescriptor(\.createdAt, order: .forward)
            ])
        )
    }

    @Test func addFavoriteAssignsIncreasingContiguousSortIndex() throws {
        let (store, context) = makeStoreAndContext()

        store.addFavorite(station("a"))
        store.addFavorite(station("b"))
        store.addFavorite(station("c"))

        let favorites = try favoritesBySortIndex(context)
        #expect(favorites.map(\.stationID) == ["a", "b", "c"])
        #expect(favorites.map(\.sortIndex) == [0, 1, 2])
    }

    @Test func moveFavoriteDownReordersAndRewritesContiguously() throws {
        let (store, context) = makeStoreAndContext()
        for id in ["a", "b", "c", "d"] { store.addFavorite(station(id)) }

        // Move the first row to the end.
        store.moveFavorites(try favoritesBySortIndex(context), from: IndexSet(integer: 0), to: 4)

        let favorites = try favoritesBySortIndex(context)
        #expect(favorites.map(\.stationID) == ["b", "c", "d", "a"])
        #expect(favorites.map(\.sortIndex) == [0, 1, 2, 3])
    }

    @Test func moveFavoriteUpReordersAndRewritesContiguously() throws {
        let (store, context) = makeStoreAndContext()
        for id in ["a", "b", "c", "d"] { store.addFavorite(station(id)) }

        // Move the last row to the front.
        store.moveFavorites(try favoritesBySortIndex(context), from: IndexSet(integer: 3), to: 0)

        let favorites = try favoritesBySortIndex(context)
        #expect(favorites.map(\.stationID) == ["d", "a", "b", "c"])
        #expect(favorites.map(\.sortIndex) == [0, 1, 2, 3])
    }

    @Test func moveFavoriteWithOutOfRangeIndicesIsNoOp() throws {
        let (store, context) = makeStoreAndContext()
        for id in ["a", "b", "c"] { store.addFavorite(station(id)) }
        let favorites = try favoritesBySortIndex(context)

        // Source past the end and destination past count must not trap or reorder.
        store.moveFavorites(favorites, from: IndexSet(integer: 5), to: 1)
        store.moveFavorites(favorites, from: IndexSet(integer: 0), to: 99)

        #expect(try favoritesBySortIndex(context).map(\.stationID) == ["a", "b", "c"])
    }

    @Test func moveFavoritesWithSubsetIsNoOp() throws {
        let (store, context) = makeStoreAndContext()
        for id in ["a", "b", "c", "d"] { store.addFavorite(station(id)) }

        let subset = Array(try favoritesBySortIndex(context).dropFirst())
        store.moveFavorites(subset, from: IndexSet(integer: 0), to: 2)

        #expect(try favoritesBySortIndex(context).map(\.stationID) == ["a", "b", "c", "d"])
    }

    @Test func backfillNormalizesLegacyRowsByCreatedAtDescending() throws {
        let (_, context) = makeStoreAndContext()

        // Simulate a pre-migration store: every row shares sortIndex 0.
        let old = FavoriteStation(stationID: "old", name: "Old", genre: "T", createdAt: .now.addingTimeInterval(-120))
        let mid = FavoriteStation(stationID: "mid", name: "Mid", genre: "T", createdAt: .now.addingTimeInterval(-60))
        let new = FavoriteStation(stationID: "new", name: "New", genre: "T", createdAt: .now)
        for favorite in [old, mid, new] { context.insert(favorite) }
        try context.save()

        // Constructing a new store triggers the one-time normalization.
        _ = LibraryStore(context: context)

        let favorites = try favoritesBySortIndex(context)
        #expect(favorites.map(\.stationID) == ["new", "mid", "old"])
        #expect(favorites.map(\.sortIndex) == [0, 1, 2])
    }

    @Test func backfillSkipsNonLegacyDuplicateIndices() throws {
        let (_, context) = makeStoreAndContext()

        let oldest = FavoriteStation(
            stationID: "oldest",
            name: "Oldest",
            genre: "T",
            createdAt: .now.addingTimeInterval(-180),
            sortIndex: 5
        )
        let middle = FavoriteStation(
            stationID: "middle",
            name: "Middle",
            genre: "T",
            createdAt: .now.addingTimeInterval(-120),
            sortIndex: 1
        )
        let newest = FavoriteStation(
            stationID: "newest",
            name: "Newest",
            genre: "T",
            createdAt: .now,
            sortIndex: 1
        )
        for favorite in [oldest, middle, newest] { context.insert(favorite) }
        try context.save()

        _ = LibraryStore(context: context)

        let favorites = try favoritesBySortIndex(context)
        #expect(favorites.map(\.stationID) == ["middle", "newest", "oldest"])
        #expect(favorites.map(\.sortIndex) == [1, 1, 5])
    }

    @Test func backfillIsNoOpWhenIndicesAlreadyDistinct() throws {
        let (store, context) = makeStoreAndContext()
        for id in ["a", "b", "c"] { store.addFavorite(station(id)) }

        let before = try favoritesBySortIndex(context).map { ($0.stationID, $0.sortIndex) }

        // A fresh store over the same context must not disturb an existing arrangement.
        _ = LibraryStore(context: context)

        let after = try favoritesBySortIndex(context).map { ($0.stationID, $0.sortIndex) }
        #expect(before.map(\.0) == after.map(\.0))
        #expect(before.map(\.1) == after.map(\.1))
    }

    @Test func deletingFavoriteKeepsRemainingOrderStable() throws {
        let (store, context) = makeStoreAndContext()
        for id in ["a", "b", "c"] { store.addFavorite(station(id)) }

        store.removeFavorite(stationID: "b")

        let favorites = try favoritesBySortIndex(context)
        #expect(favorites.map(\.stationID) == ["a", "c"])
    }

    @Test func removingRecentDeletesItFromHistory() throws {
        let (store, context) = makeStoreAndContext()

        store.logRecent(station("a"))
        store.logRecent(station("b"))
        store.logRecent(station("c"))

        store.removeRecent(stationID: "b")

        let descriptor = FetchDescriptor<RecentStation>(
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
        )
        let recents = try context.fetch(descriptor)
        let ids = recents.map(\.stationID)
        #expect(ids.contains("b") == false)
        #expect(ids.contains("a"))
        #expect(ids.contains("c"))
    }

    @Test func hidingFromListenNowSetsFlagButKeepsTheRecord() throws {
        let (store, context) = makeStoreAndContext()
        store.logRecent(station("a"))

        store.hideFromListenNow(stationID: "a")

        let recents = try context.fetch(FetchDescriptor<RecentStation>())
        #expect(recents.count == 1, "the play record must survive a Listen Now dismiss")
        #expect(recents.first?.isHiddenFromListenNow == true)
    }

    @Test func unhidingFromListenNowClearsTheFlag() throws {
        let (store, context) = makeStoreAndContext()
        store.logRecent(station("a"))
        store.hideFromListenNow(stationID: "a")

        store.unhideFromListenNow(stationID: "a")

        let recents = try context.fetch(FetchDescriptor<RecentStation>())
        #expect(recents.count == 1)
        #expect(recents.first?.isHiddenFromListenNow == false)
    }

    @Test func unhidingNonExistentRecentIsNoOp() throws {
        let (store, context) = makeStoreAndContext()
        store.logRecent(station("a"))

        store.unhideFromListenNow(stationID: "does-not-exist")

        let recents = try context.fetch(FetchDescriptor<RecentStation>())
        #expect(recents.count == 1)
        #expect(recents.first?.isHiddenFromListenNow == false)
    }

    @Test func rePlayingAHiddenRecentUnhidesIt() throws {
        let (store, context) = makeStoreAndContext()
        store.logRecent(station("a"))
        store.hideFromListenNow(stationID: "a")

        store.logRecent(station("a"))

        let recents = try context.fetch(FetchDescriptor<RecentStation>())
        #expect(recents.first?.isHiddenFromListenNow == false)
    }

    @Test func hidingNonExistentRecentIsNoOp() throws {
        let (store, context) = makeStoreAndContext()
        store.logRecent(station("a"))

        store.hideFromListenNow(stationID: "does-not-exist")

        let recents = try context.fetch(FetchDescriptor<RecentStation>())
        #expect(recents.count == 1)
        #expect(recents.first?.isHiddenFromListenNow == false)
    }

    @Test func removingNonExistentRecentIsNoOp() throws {
        let (store, context) = makeStoreAndContext()

        store.logRecent(station("a"))
        store.removeRecent(stationID: "does-not-exist")

        let recents = try context.fetch(FetchDescriptor<RecentStation>())
        #expect(recents.count == 1)
    }

    @Test func loggingSameStationTwiceKeepsOneRecent() throws {
        let (store, context) = makeStoreAndContext()

        store.logRecent(station("a"))
        store.logRecent(station("a"))

        let recents = try context.fetch(FetchDescriptor<RecentStation>())
        #expect(recents.count == 1)
        #expect(recents.first?.stationID == "a")
    }

    @Test func mostRecentStationReturnsNewestPlay() {
        let (store, _) = makeStoreAndContext()

        store.logRecent(station("a"))
        store.logRecent(station("b"))

        #expect(store.mostRecentStation()?.id == "b")
    }

    @Test func mostRecentStationReturnsNilWithoutHistory() {
        let (store, _) = makeStoreAndContext()

        #expect(store.mostRecentStation() == nil)
    }

    // MARK: - Play count

    @Test func firstPlayStartsCountAtOne() throws {
        let (store, context) = makeStoreAndContext()

        store.logRecent(station("a"))

        let recents = try context.fetch(FetchDescriptor<RecentStation>())
        #expect(recents.first?.playCount == 1)
    }

    @Test func replayingIncrementsPlayCount() throws {
        let (store, context) = makeStoreAndContext()

        store.logRecent(station("a"))
        store.logRecent(station("a"))
        store.logRecent(station("a"))

        let recents = try context.fetch(FetchDescriptor<RecentStation>())
        #expect(recents.count == 1)
        #expect(recents.first?.playCount == 3)
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

    @Test func recentsTrimClearsBacklogBeyondSingleBatch() throws {
        let (store, context) = makeStoreAndContext()
        let total = LibraryStore.recentsLimit + LibraryStore.recentsTrimHeadroom + 25

        for index in 0..<total {
            context.insert(
                RecentStation(
                    stationID: "seed\(index)",
                    name: "Seed \(index)",
                    genre: "Test",
                    playedAt: .now.addingTimeInterval(TimeInterval(-index))
                )
            )
        }
        try context.save()

        store.logRecent(station("fresh"))

        let count = try context.fetch(FetchDescriptor<RecentStation>()).count
        #expect(count <= LibraryStore.recentsLimit)
    }

}
