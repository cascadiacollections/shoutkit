import Foundation
@testable import Persistence
import RadioDirectory
import SwiftData
import Testing

/// Fixtures duplicated from LibraryStoreTests.swift: file-private on purpose so
/// each suite file stays self-contained.
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
            FetchDescriptor<FavoriteStation>(sortBy: [SortDescriptor(\.sortIndex, order: .forward)]),
        )
    }

    private func streamableStation(_ id: String) -> Station {
        Station(
            id: id,
            name: "Station \(id)",
            genre: "Test",
            listenerCount: 10,
            preferredStreamURL: URL(string: "https://example.com/\(id).aac"),
        )
    }

    @Test func `prewarm UR ls rank favorites first then most played recents`() throws {
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

    @Test func `ranked stations follow favorite then most played recent ordering`() {
        let (store, _) = makeStoreAndContext()

        store.logRecent(streamableStation("a"))
        store.logRecent(streamableStation("b"))
        store.logRecent(streamableStation("b"))
        store.addFavorite(streamableStation("fav"))

        let rankedIDs = store.rankedStations(limit: 5).map(\.id)

        #expect(rankedIDs == ["fav", "b", "a"])
    }

    @Test func `ranked stations deduplicate favorites and recents`() {
        let (store, _) = makeStoreAndContext()
        let station = streamableStation("dup")

        store.addFavorite(station)
        store.logRecent(station)
        store.logRecent(streamableStation("other"))

        let rankedIDs = store.rankedStations(limit: 5).map(\.id)

        #expect(rankedIDs == ["dup", "other"])
    }

    @Test func `prewarm UR ls are capped at limit and deduplicated`() {
        let (store, _) = makeStoreAndContext()
        for index in 0 ..< 10 {
            store.logRecent(streamableStation("s\(index)"))
        }

        let urls = store.prewarmStreamURLs(limit: 3)

        #expect(urls.count == 3)
        #expect(Set(urls).count == 3)
    }

    @Test func `prewarm UR ls skip stations without A snapshot URL`() {
        let (store, _) = makeStoreAndContext()
        store.logRecent(station("no-url")) // helper leaves preferredStreamURL nil

        #expect(store.prewarmStreamURLs(limit: 5).isEmpty)
    }

    @Test func `favorite stations respect manual ordering`() throws {
        let (store, context) = makeStoreAndContext()
        for id in ["a", "b", "c"] {
            store.addFavorite(streamableStation(id))
        }

        try store.moveFavorites(favoritesBySortIndex(context), from: IndexSet(integer: 2), to: 0)

        #expect(store.favoriteStations().map(\.id) == ["c", "a", "b"])
    }

    @Test func `ranked stations stop after the limit instead of later favorites`() {
        let (store, _) = makeStoreAndContext()
        for index in 0 ..< 30 {
            store.addFavorite(streamableStation("fav-\(index)"))
        }
        store.logRecent(streamableStation("recent"))
        store.logRecent(streamableStation("recent"))

        let rankedIDs = store.rankedStations(limit: 5).map(\.id)

        #expect(rankedIDs == ["fav-0", "fav-1", "fav-2", "fav-3", "fav-4"])
    }

    @Test func `ranked stations skip a duplicate recent while filling the limit`() {
        let (store, _) = makeStoreAndContext()
        store.addFavorite(streamableStation("fav"))
        // Played twice so this recent sorts ahead of "other" and would be the
        // only row a `fetchLimit` of (limit - favorites) would see.
        store.logRecent(streamableStation("fav"))
        store.logRecent(streamableStation("fav"))
        store.logRecent(streamableStation("other"))

        #expect(store.rankedStations(limit: 2).map(\.id) == ["fav", "other"])
    }

    @Test func `ranked stations keep a favorite that has no stream URL`() {
        let (store, _) = makeStoreAndContext()
        store.addFavorite(station("no-url"))
        store.logRecent(streamableStation("recent"))

        #expect(store.rankedStations(limit: 5).map(\.id) == ["no-url", "recent"])
    }

    @Test func `prewarm UR ls keep walking past favorites with no snapshot`() {
        let (store, _) = makeStoreAndContext()
        for index in 0 ..< 6 {
            store.addFavorite(station("no-url-\(index)"))
        }
        store.addFavorite(streamableStation("has-url"))
        store.logRecent(streamableStation("recent-url"))

        let urls = store.prewarmStreamURLs(limit: 2).map(\.absoluteString)

        #expect(urls == [
            "https://example.com/has-url.aac",
            "https://example.com/recent-url.aac",
        ])
    }

    @Test func `prewarm UR ls collapse stations that share a snapshot URL`() throws {
        let (store, _) = makeStoreAndContext()
        let shared = try #require(URL(string: "https://example.com/shared.aac"))
        let station = { (id: String) in
            Station(
                id: id,
                name: "Station \(id)",
                genre: "Test",
                listenerCount: 10,
                preferredStreamURL: shared,
            )
        }
        store.addFavorite(station("a"))
        store.addFavorite(station("b"))
        store.logRecent(streamableStation("c"))

        #expect(store.prewarmStreamURLs(limit: 5).map(\.absoluteString) == [
            shared.absoluteString,
            "https://example.com/c.aac",
        ])
    }

    @Test func `refreshing stream URL snapshot updates favorites and matching recents`() throws {
        let (store, context) = makeStoreAndContext()
        let stale = try #require(URL(string: "https://example.com/stale.aac"))
        let fresh = try #require(URL(string: "https://example.com/fresh.aac"))
        let station = Station(
            id: "fav",
            name: "Favorite",
            genre: "Test",
            listenerCount: 10,
            preferredStreamURL: stale,
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
