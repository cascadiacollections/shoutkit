import SwiftData

/// Version 1 of the library schema: favorites, recently played stations and
/// recently heard tracks, exactly as the models in `RadioModels.swift` stood on
/// 2026-11-22.
///
/// It lists the live model classes, which is right for as long as it is the
/// newest version. Any change to a stored property of those classes needs a
/// new version first; `CONTRIBUTING.md` ("Changing a SwiftData model") has the
/// steps, and `ShoutKitSchemaTests` fails until they are followed.
public enum ShoutKitSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
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
        [ShoutKitSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}
