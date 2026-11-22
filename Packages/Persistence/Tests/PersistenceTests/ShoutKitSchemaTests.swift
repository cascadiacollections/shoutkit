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
    private static let shippedShape = [
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
    ]

    private static func attributeNames(of version: any VersionedSchema.Type) -> [String: [String]] {
        Dictionary(
            uniqueKeysWithValues: Schema(versionedSchema: version).entities.map { entity in
                (entity.name, entity.attributes.map(\.name).sorted())
            },
        )
    }

    private static func uniqueAttributes(of version: any VersionedSchema.Type) -> [String: [[String]]] {
        Dictionary(
            uniqueKeysWithValues: Schema(versionedSchema: version).entities.map { entity in
                (entity.name, entity.uniquenessConstraints)
            },
        )
    }

    /// These two fail when a stored property is added, removed or renamed
    /// without a new schema version. Do not edit the lists to make them pass:
    /// follow "Changing a SwiftData model" in CONTRIBUTING.md, then pin the new
    /// version here too.
    @Test func `version 1 still has the shape it shipped with`() {
        #expect(Self.attributeNames(of: ShoutKitSchemaV1.self) == Self.shippedShape)
        #expect(Self.uniqueAttributes(of: ShoutKitSchemaV1.self) == [
            "FavoriteStation": [["stationID"]],
            "RecentStation": [["stationID"]],
            "RecentlyHeardTrack": [],
        ])
    }

    @Test func `version 2 has the same attributes and nothing unique`() {
        #expect(Self.attributeNames(of: ShoutKitSchemaV2.self) == Self.shippedShape)
        #expect(Self.uniqueAttributes(of: ShoutKitSchemaV2.self).values.allSatisfy(\.isEmpty))
    }

    /// CloudKit refuses a non-optional attribute that has no default.
    @Test func `every required attribute in version 2 has a default`() {
        for entity in Schema(versionedSchema: ShoutKitSchemaV2.self).entities {
            for attribute in entity.attributes where attribute.isOptional == false {
                #expect(attribute.defaultValue != nil, "\(entity.name).\(attribute.name) has no default")
            }
        }
    }

    @Test func `the migration plan ends at the schema the container opens`() {
        #expect(ShoutKitMigrationPlan.schemas.last?.versionIdentifier == ShoutKitSchemaV2.versionIdentifier)
        #expect(ShoutKitMigrationPlan.stages.count == ShoutKitMigrationPlan.schemas.count - 1)
    }

    /// Stores on devices are in the version 1 shape, written either with no
    /// versioned schema (builds before the plan) or with one. Both must migrate
    /// to version 2 through the plan itself, not through the fallback open.
    @Test(arguments: [false, true])
    func `a version 1 store migrates through the plan with its rows`(versioned: Bool) throws {
        let url = try Self.temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let old = versioned ? Schema(versionedSchema: ShoutKitSchemaV1.self) : Schema(ShoutKitSchemaV1.models)
            let container = try ModelContainer(for: old, configurations: [ModelConfiguration(schema: old, url: url)])
            let context = ModelContext(container)
            context.insert(
                ShoutKitSchemaV1.FavoriteStation(stationID: "kexp", name: "KEXP", genre: "Eclectic", sortIndex: 3),
            )
            context.insert(
                ShoutKitSchemaV1.RecentStation(stationID: "kexp", name: "KEXP", genre: "Eclectic", playCount: 7),
            )
            context.insert(
                ShoutKitSchemaV1.RecentlyHeardTrack(stationID: "kexp", stationName: "KEXP", title: "Song"),
            )
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
        #expect(try context.fetch(FetchDescriptor<RecentlyHeardTrack>()).map(\.title) == ["Song"])

        // The constraint is gone after the migration, not only in a new store.
        context.insert(FavoriteStation(stationID: "kexp", name: "KEXP again", genre: "Eclectic"))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<FavoriteStation>()) == 2)
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
