import SwiftData

/// Version 2 of the library schema, and the current one: the live model
/// classes in `RadioModels.swift`.
///
/// It differs from ``ShoutKitSchemaV1`` in what CloudKit requires: `stationID`
/// is no longer unique, and every non-optional property has a default. Any
/// further change to a stored property needs a new version first;
/// `CONTRIBUTING.md` ("Changing a SwiftData model") has the steps, and
/// `ShoutKitSchemaTests` fails until they are followed.
public enum ShoutKitSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        [
            FavoriteStation.self,
            RecentStation.self,
            RecentlyHeardTrack.self,
        ]
    }
}

/// Every version the library store has had, oldest first, and how to get from
/// each to the next. ``ShoutKitModelContainer`` opens the store with it.
public enum ShoutKitMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [ShoutKitSchemaV1.self, ShoutKitSchemaV2.self]
    }

    public static var stages: [MigrationStage] {
        [
            // Dropping a uniqueness constraint and adding defaults rewrites no rows.
            .lightweight(fromVersion: ShoutKitSchemaV1.self, toVersion: ShoutKitSchemaV2.self),
        ]
    }
}
