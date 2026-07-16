import Foundation
import RadioDirectory
import SwiftData
import Testing

@testable import Persistence

// Fixtures duplicated from LibraryStoreTests.swift: file-private on purpose so
// each suite file stays self-contained.
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
struct LibraryStoreRankingTests {
    private func favoritesBySortIndex(_ context: ModelContext) throws -> [FavoriteStation] {
        try context.fetch(
            FetchDescriptor<FavoriteStation>(sortBy: [SortDescriptor(\.sortIndex, order: .forward)])
        )
    }

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
}
