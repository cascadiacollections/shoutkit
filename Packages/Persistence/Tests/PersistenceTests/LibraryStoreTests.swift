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
        try context.fetch(
            FetchDescriptor<FavoriteStation>(sortBy: [SortDescriptor(\.sortIndex, order: .forward)])
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

    // MARK: - Prewarm ranking

    private func streamableStation(_ id: String) -> Station {
        Station(
            id: id,
            name: "Station \(id)",
            genre: "Test",
            listenerCount: 10,
            preferredStreamURL: URL(string: "https://example.com/\(id).aac")
        )
    }

    @Test func prewarmURLsRankFavoritesFirstThenMostPlayedRecents() throws {
        let (store, _) = makeStoreAndContext()

        // "b" is played most; "a" played once; "fav" is a favorite (weaker
        // recency but stronger intent → should come first).
        store.logRecent(streamableStation("a"))
        store.logRecent(streamableStation("b"))
        store.logRecent(streamableStation("b"))
        store.addFavorite(streamableStation("fav"))

        let urls = store.prewarmStreamURLs(limit: 5).map(\.absoluteString)

        #expect(urls.first == "https://example.com/fav.aac")
        // Among recents, higher playCount ("b") outranks lower ("a").
        let bIndex = try #require(urls.firstIndex(of: "https://example.com/b.aac"))
        let aIndex = try #require(urls.firstIndex(of: "https://example.com/a.aac"))
        #expect(bIndex < aIndex)
    }

    @Test func rankedStationsFollowFavoriteThenMostPlayedRecentOrdering() throws {
        let (store, _) = makeStoreAndContext()

        store.logRecent(streamableStation("a"))
        store.logRecent(streamableStation("b"))
        store.logRecent(streamableStation("b"))
        store.addFavorite(streamableStation("fav"))

        let rankedIDs = store.rankedStations(limit: 5).map(\.id)

        #expect(rankedIDs == ["fav", "b", "a"])
    }

    @Test func rankedStationsDeduplicateFavoritesAndRecents() throws {
        let (store, _) = makeStoreAndContext()
        let station = streamableStation("dup")

        store.addFavorite(station)
        store.logRecent(station)
        store.logRecent(streamableStation("other"))

        let rankedIDs = store.rankedStations(limit: 5).map(\.id)

        #expect(rankedIDs == ["dup", "other"])
    }

    @Test func prewarmURLsAreCappedAtLimitAndDeduplicated() throws {
        let (store, _) = makeStoreAndContext()
        for index in 0..<10 { store.logRecent(streamableStation("s\(index)")) }

        let urls = store.prewarmStreamURLs(limit: 3)

        #expect(urls.count == 3)
        #expect(Set(urls).count == 3)
    }

    @Test func prewarmURLsSkipStationsWithoutASnapshotURL() throws {
        let (store, _) = makeStoreAndContext()
        store.logRecent(station("no-url")) // helper leaves preferredStreamURL nil

        #expect(store.prewarmStreamURLs(limit: 5).isEmpty)
    }

    @Test func favoriteStationsRespectManualOrdering() throws {
        let (store, context) = makeStoreAndContext()
        for id in ["a", "b", "c"] { store.addFavorite(streamableStation(id)) }

        store.moveFavorites(try favoritesBySortIndex(context), from: IndexSet(integer: 2), to: 0)

        #expect(store.favoriteStations().map(\.id) == ["c", "a", "b"])
    }

    @Test func refreshingStreamURLSnapshotUpdatesFavoritesAndMatchingRecents() throws {
        let (store, context) = makeStoreAndContext()
        let stale = try #require(URL(string: "https://example.com/stale.aac"))
        let fresh = try #require(URL(string: "https://example.com/fresh.aac"))
        let station = Station(
            id: "fav",
            name: "Favorite",
            genre: "Test",
            listenerCount: 10,
            preferredStreamURL: stale
        )

        store.addFavorite(station)
        store.logRecent(station)
        store.refreshStreamURLSnapshot(stationID: "fav", streamURL: fresh)

        let favorites = try context.fetch(FetchDescriptor<FavoriteStation>())
        let recents = try context.fetch(FetchDescriptor<RecentStation>())
        #expect(favorites.first?.streamURLString == fresh.absoluteString)
        #expect(recents.first?.streamURLString == fresh.absoluteString)
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
