import Foundation
@testable import Persistence
import SwiftData
import Testing

/// A favorite as the store held it before `sortIndex` existed. The class is
/// nested so that its entity is still named `FavoriteStation`.
enum LegacyLibraryShape {
    @Model
    final class FavoriteStation {
        @Attribute(.unique) var stationID: String
        var name: String
        var genre: String
        var artworkURLString: String?
        var streamURLString: String?
        var createdAt: Date

        init(stationID: String, name: String, genre: String, createdAt: Date = .now) {
            self.stationID = stationID
            self.name = name
            self.genre = genre
            self.createdAt = createdAt
        }
    }
}

@MainActor
struct ShoutKitSchemaTests {
    /// Fails when a stored property is added, removed or renamed without a new
    /// schema version. Do not edit the lists to make it pass: follow "Changing a
    /// SwiftData model" in CONTRIBUTING.md, then pin the new version here too.
    @Test func `version 1 still has the shape it shipped with`() {
        let shape = Dictionary(
            uniqueKeysWithValues: Schema(versionedSchema: ShoutKitSchemaV1.self).entities.map { entity in
                (entity.name, entity.attributes.map(\.name).sorted())
            },
        )

        #expect(shape == [
            "FavoriteStation": [
                "artworkURLString", "createdAt", "genre", "name", "sortIndex", "stationID", "streamURLString",
            ],
            "RecentStation": [
                "artworkURLString", "bitrate", "clickTrend", "codec", "country", "genre",
                "isHiddenFromListenNow", "language", "name", "playCount", "playedAt", "stationID",
                "streamURLString", "tagsCSV", "votes",
            ],
            "RecentlyHeardTrack": [
                "appleMusicURLString", "artist", "artworkURLString", "heardAt", "stationID", "stationName",
                "title",
            ],
        ])
    }

    @Test func `the migration plan ends at the schema the container opens`() {
        #expect(ShoutKitMigrationPlan.schemas.last?.versionIdentifier == ShoutKitSchemaV1.versionIdentifier)
        #expect(ShoutKitMigrationPlan.stages.count == ShoutKitMigrationPlan.schemas.count - 1)
    }

    /// The stores already on devices were written without a versioned schema.
    /// This is the claim the whole change rests on: the plan accepts them as V1.
    @Test func `a store written before the plan opens under it with its rows`() throws {
        let url = try Self.temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let unversioned = Schema([FavoriteStation.self, RecentStation.self, RecentlyHeardTrack.self])
            let container = try ModelContainer(
                for: unversioned,
                configurations: [ModelConfiguration(schema: unversioned, url: url)],
            )
            let context = ModelContext(container)
            context.insert(FavoriteStation(stationID: "kexp", name: "KEXP", genre: "Eclectic", sortIndex: 3))
            context.insert(RecentStation(stationID: "kexp", name: "KEXP", genre: "Eclectic", playCount: 7))
            try context.save()
        }

        let schema = ShoutKitModelContainer.schema
        let container = try ModelContainer(
            for: schema,
            migrationPlan: ShoutKitMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, url: url)],
        )
        let context = ModelContext(container)

        #expect(try context.fetch(FetchDescriptor<FavoriteStation>()).map(\.sortIndex) == [3])
        #expect(try context.fetch(FetchDescriptor<RecentStation>()).map(\.playCount) == [7])
    }

    /// A store last written by a build older than V1 has a shape the plan does
    /// not list. Whichever open accepts it, the favorites must survive.
    @Test func `a store older than version 1 still opens with its rows`() throws {
        let url = try Self.temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let legacy = Schema([LegacyLibraryShape.FavoriteStation.self])
            let container = try ModelContainer(
                for: legacy,
                configurations: [ModelConfiguration(schema: legacy, url: url)],
            )
            let context = ModelContext(container)
            context.insert(LegacyLibraryShape.FavoriteStation(stationID: "kexp", name: "KEXP", genre: "Eclectic"))
            try context.save()
        }

        let container = ShoutKitModelContainer.makeContainer(url: url)

        #expect(ShoutKitModelContainer.isPersistentStoreAvailable)
        let favorites = try ModelContext(container).fetch(FetchDescriptor<FavoriteStation>())
        #expect(favorites.map(\.stationID) == ["kexp"])
        #expect(favorites.map(\.sortIndex) == [0])
    }

    private static func temporaryStoreURL() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShoutKitSchemaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("library.store")
    }
}
