import Foundation
import SwiftData
#if canImport(OSLog)
    import OSLog
#endif

public enum ShoutKitModelContainer {
    /// The SwiftData schema backing favorites, recents, and recently heard
    /// tracks: the newest version in ``ShoutKitMigrationPlan``.
    public static let schema = Schema(versionedSchema: ShoutKitSchemaV2.self)

    /// `false` when opening the persistent on-disk store failed and the app is
    /// running against a fallback in-memory store.
    @MainActor
    public private(set) static var isPersistentStoreAvailable = true

    /// `true` when the container returned by the last `makeContainer` call was
    /// opened with iCloud sync. `false` when sync was not asked for, or was
    /// asked for and the store had to be opened without it.
    @MainActor
    public private(set) static var isCloudSyncActive = false

    #if canImport(OSLog)
        private static let logger = Logger(subsystem: "ShoutKit.Persistence", category: "ShoutKitModelContainer")
    #endif

    /// Builds the app-wide persistent container. Falls back to an in-memory
    /// store if the on-disk store cannot be opened so the UI still functions.
    ///
    /// - Parameter cloudKitContainerIdentifier: The iCloud container whose
    ///   private database the library syncs with, or `nil` to keep it on this
    ///   device. **The process must have the matching iCloud entitlement:**
    ///   without it CloudKit kills the process instead of throwing, so check
    ///   ``CloudSyncEntitlement`` before passing one. If the store cannot be
    ///   opened with sync for a reason that does throw, it is opened without
    ///   it, and ``isCloudSyncActive`` says which happened. Ignored when
    ///   `inMemory`.
    @MainActor
    public static func makeContainer(
        inMemory: Bool = false,
        cloudKitContainerIdentifier: String? = nil,
    ) -> ModelContainer {
        isCloudSyncActive = false
        if inMemory {
            let configuration = inMemoryConfiguration()
            return makeContainer(opens: [{ try openWithMigrationPlan(configuration) }])
        }

        var opens = localOpens(ModelConfiguration(schema: schema, cloudKitDatabase: .none))
        if let cloudKitContainerIdentifier {
            let synced = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudKitContainerIdentifier))
            opens.insert({
                let container = try openWithMigrationPlan(synced)
                isCloudSyncActive = true
                return container
            }, at: 0)
        }
        return makeContainer(opens: opens)
    }

    /// The production open sequence, without sync, against a store file at `url`.
    @MainActor
    static func makeContainer(url: URL) -> ModelContainer {
        makeContainer(opens: localOpens(ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)))
    }

    /// Runs `open` once for an in-memory store and up to twice for the on-disk one.
    @MainActor
    static func makeContainer(
        inMemory: Bool,
        open: @escaping (ModelConfiguration) throws -> ModelContainer,
    ) -> ModelContainer {
        if inMemory {
            let configuration = inMemoryConfiguration()
            return makeContainer(opens: [{ try open(configuration) }])
        }
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        return makeContainer(opens: [{ try open(configuration) }, { try open(configuration) }])
    }

    /// Tries each of `opens` in order and returns the first container that
    /// opens; with none, marks the store unavailable and returns an in-memory one.
    @MainActor
    static func makeContainer(opens: [@MainActor () throws -> ModelContainer]) -> ModelContainer {
        isPersistentStoreAvailable = true
        for (index, open) in opens.enumerated() {
            do {
                return try open()
            } catch {
                logStoreOpenFailure(error, retrying: index < opens.count - 1)
            }
        }

        isPersistentStoreAvailable = false
        let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        // Last-resort in-memory container keeps the app usable if disk fails;
        // in-memory construction has no failure mode worth surviving past.
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: schema, configurations: [fallback])
    }

    /// With the migration plan first. If that fails, once more without it: a
    /// staged migration refuses a store whose shape matches no listed version,
    /// which is what a store last written by a build older than
    /// ``ShoutKitSchemaV1`` looks like. Opening without the plan migrates such
    /// a store the way every build before the plan did (DECISIONS.md, 2026-11-22).
    @MainActor
    private static func localOpens(_ configuration: ModelConfiguration) -> [@MainActor () throws -> ModelContainer] {
        [
            { try openWithMigrationPlan(configuration) },
            { try ModelContainer(for: schema, configurations: [configuration]) },
        ]
    }

    private static func openWithMigrationPlan(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, migrationPlan: ShoutKitMigrationPlan.self, configurations: [configuration])
    }

    private static func inMemoryConfiguration() -> ModelConfiguration {
        ModelConfiguration(
            "ShoutKitInMemory-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none,
        )
    }

    private static func logStoreOpenFailure(_ error: Error, retrying: Bool) {
        let message = if retrying {
            "Failed to open persistent SwiftData store; trying the next way to open it: \(error)"
        } else {
            "Failed to open persistent SwiftData store; using in-memory fallback store: \(error)"
        }
        #if canImport(OSLog)
            logger.fault("\(message, privacy: .public)")
        #else
            print(message)
        #endif
    }
}
