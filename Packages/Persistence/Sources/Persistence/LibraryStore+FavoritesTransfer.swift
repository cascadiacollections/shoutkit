import Foundation

public struct FavoritesTransferDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var favorites: [Favorite]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        favorites: [Favorite]
    ) {
        self.schemaVersion = schemaVersion
        self.favorites = favorites
    }
}

public extension FavoritesTransferDocument {
    struct Favorite: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var streamURL: String?
        public var genre: String
        public var artworkURL: String?
        public var sortIndex: Int

        public init(
            id: String,
            name: String,
            streamURL: String?,
            genre: String,
            artworkURL: String?,
            sortIndex: Int
        ) {
            self.id = id
            self.name = name
            self.streamURL = streamURL
            self.genre = genre
            self.artworkURL = artworkURL
            self.sortIndex = sortIndex
        }

        init(favorite: FavoriteStation) {
            self.init(
                id: favorite.stationID,
                name: favorite.name,
                streamURL: favorite.streamURLString,
                genre: favorite.genre,
                artworkURL: favorite.artworkURLString,
                sortIndex: favorite.sortIndex
            )
        }
    }
}

public struct FavoritesImportResult: Equatable, Sendable {
    public let addedCount: Int
    public let skippedExistingCount: Int

    public init(addedCount: Int, skippedExistingCount: Int) {
        self.addedCount = addedCount
        self.skippedExistingCount = skippedExistingCount
    }
}

public enum FavoritesTransferError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported favorites backup format version: \(version)."
        case .saveFailed(let message):
            message
        }
    }
}

@MainActor
public extension LibraryStore {
    func exportFavoritesJSONData() throws -> Data {
        let document = FavoritesTransferDocument(
            favorites: orderedFavorites().map(FavoritesTransferDocument.Favorite.init(favorite:))
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    func importFavoritesJSONData(_ data: Data) throws -> FavoritesImportResult {
        let decoder = JSONDecoder()
        let document = try decoder.decode(FavoritesTransferDocument.self, from: data)
        guard document.schemaVersion == FavoritesTransferDocument.currentSchemaVersion else {
            throw FavoritesTransferError.unsupportedSchemaVersion(document.schemaVersion)
        }

        let existingFavorites = orderedFavorites()
        var existingIDs = Set(existingFavorites.map(\.stationID))
        let hasExistingFavorites = existingFavorites.isEmpty == false
        let nextSortIndexStart = (existingFavorites.map(\.sortIndex).max() ?? -1) + 1

        let sortedImportedFavorites = normalizeImportedFavorites(document.favorites)

        var addedCount = 0
        var skippedExistingCount = 0

        for favorite in sortedImportedFavorites {
            guard existingIDs.contains(favorite.id) == false else {
                skippedExistingCount += 1
                continue
            }

            context.insert(
                FavoriteStation(
                    stationID: favorite.id,
                    name: favorite.name,
                    genre: favorite.genre,
                    artworkURLString: favorite.artworkURL,
                    streamURLString: favorite.streamURL,
                    sortIndex: hasExistingFavorites ? nextSortIndexStart + addedCount : favorite.sortIndex
                )
            )
            existingIDs.insert(favorite.id)
            favoriteIDs.insert(favorite.id)
            addedCount += 1
        }

        if addedCount > 0 {
            guard save(operation: "import favorites backup") else {
                throw FavoritesTransferError.saveFailed(
                    lastErrorMessage ?? "Could not save imported favorites."
                )
            }
        }

        return FavoritesImportResult(
            addedCount: addedCount,
            skippedExistingCount: skippedExistingCount
        )
    }

    private func normalizeImportedFavorites(
        _ favorites: [FavoritesTransferDocument.Favorite]
    ) -> [FavoritesTransferDocument.Favorite] {
        var seenIDs = Set<String>()
        return favorites
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.sortIndex == rhs.element.sortIndex {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.sortIndex < rhs.element.sortIndex
            }
            .compactMap { _, favorite in
                guard favorite.id.isEmpty == false,
                      seenIDs.insert(favorite.id).inserted else { return nil }
                return favorite
            }
    }
}
