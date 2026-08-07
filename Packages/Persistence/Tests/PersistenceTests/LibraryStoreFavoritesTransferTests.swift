import Foundation
import RadioDirectory
import SwiftData
import Testing

@testable import Persistence

@MainActor
private func makeTransferStoreAndContext() -> (LibraryStore, ModelContext) {
    let container = ShoutKitModelContainer.makeContainer(inMemory: true)
    let context = ModelContext(container)
    return (LibraryStore(context: context), context)
}

private func transferStation(_ id: String) -> Station {
    Station(id: id, name: "Station \(id)", genre: "Test", listenerCount: 10)
}

@MainActor
struct LibraryStoreFavoritesTransferTests {
    @Test func exportIncludesSchemaAndOrderedFavorites() throws {
        let (store, _) = makeTransferStoreAndContext()
        store.addFavorite(transferStation("a"))
        store.addFavorite(transferStation("b"))

        let data = try store.exportFavoritesJSONData()
        let document = try JSONDecoder().decode(FavoritesTransferDocument.self, from: data)

        #expect(document.schemaVersion == FavoritesTransferDocument.currentSchemaVersion)
        #expect(document.favorites.map(\.id) == ["a", "b"])
        #expect(document.favorites.map(\.sortIndex) == [0, 1])
    }

    @Test func importMergesByStationIDAndAppendsNewFavorites() throws {
        let (store, context) = makeTransferStoreAndContext()
        store.addFavorite(transferStation("a"))
        store.addFavorite(transferStation("b"))

        let document = FavoritesTransferDocument(
            favorites: [
                .init(id: "b", name: "B", streamURL: "https://b.example/stream", genre: "Jazz", artworkURL: nil, sortIndex: 0),
                .init(id: "c", name: "C", streamURL: "https://c.example/stream", genre: "Rock", artworkURL: nil, sortIndex: 1),
                .init(id: "d", name: "D", streamURL: "https://d.example/stream", genre: "Talk", artworkURL: nil, sortIndex: 2)
            ]
        )

        let result = try store.importFavoritesJSONData(try JSONEncoder().encode(document))
        #expect(result.addedCount == 2)
        #expect(result.skippedExistingCount == 1)

        let favorites = try context.fetch(
            FetchDescriptor<FavoriteStation>(
                sortBy: [SortDescriptor(\.sortIndex, order: .forward)]
            )
        )
        #expect(favorites.map(\.stationID) == ["a", "b", "c", "d"])
        #expect(favorites.map(\.sortIndex) == [0, 1, 2, 3])
    }

    @Test func importingIntoEmptyStorePreservesSortIndexOrder() throws {
        let (store, context) = makeTransferStoreAndContext()
        let document = FavoritesTransferDocument(
            favorites: [
                .init(id: "x", name: "X", streamURL: nil, genre: "Genre", artworkURL: nil, sortIndex: 7),
                .init(id: "y", name: "Y", streamURL: nil, genre: "Genre", artworkURL: nil, sortIndex: 1),
                .init(id: "z", name: "Z", streamURL: nil, genre: "Genre", artworkURL: nil, sortIndex: 3)
            ]
        )

        _ = try store.importFavoritesJSONData(try JSONEncoder().encode(document))

        let favorites = try context.fetch(
            FetchDescriptor<FavoriteStation>(
                sortBy: [SortDescriptor(\.sortIndex, order: .forward)]
            )
        )
        #expect(favorites.map(\.stationID) == ["y", "z", "x"])
        #expect(favorites.map(\.sortIndex) == [1, 3, 7])
    }

    @Test func importRejectsUnsupportedSchemaVersion() throws {
        let (store, _) = makeTransferStoreAndContext()
        let document = FavoritesTransferDocument(
            schemaVersion: FavoritesTransferDocument.currentSchemaVersion + 1,
            favorites: []
        )

        #expect(throws: FavoritesTransferError.unsupportedSchemaVersion(document.schemaVersion)) {
            try store.importFavoritesJSONData(try JSONEncoder().encode(document))
        }
    }
}
