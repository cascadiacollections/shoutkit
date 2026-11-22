import Foundation
import SwiftData
#if canImport(OSLog)
    import OSLog
#endif

public enum ShoutKitModelContainer {
    /// The SwiftData schema backing favorites, recents, and recently heard
    /// tracks: the newest version in ``ShoutKitMigrationPlan``.
    public static let schema = Schema(versionedSchema: ShoutKitSchemaV1.self)

    /// `false` when opening the persistent on-disk store failed and the app is
    /// running against a fallback in-memory store.
    @MainActor
    public private(set) static var isPersistentStoreAvailable = true

    #if canImport(OSLog)
        private static let logger = Logger(subsystem: "ShoutKit.Persistence", category: "ShoutKitModelContainer")
    #endif

    /// Builds the app-wide persistent container. Falls back to an in-memory
    /// store if the on-disk store cannot be opened so the UI still functions.
    @MainActor
    public static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        if inMemory {
            return makeContainer(configuration: inMemoryConfiguration(), opens: [openWithMigrationPlan])
        }
        return makeContainer(
            configuration: ModelConfiguration(schema: schema, isStoredInMemoryOnly: false),
            opens: productionOpens,
        )
    }

    /// The production open sequence against a store file at `url`.
    @MainActor
    static func makeContainer(url: URL) -> ModelContainer {
        makeContainer(configuration: ModelConfiguration(schema: schema, url: url), opens: productionOpens)
    }

    /// Runs `open` once for an in-memory store and up to twice for the on-disk one.
    @MainActor
    static func makeContainer(
        inMemory: Bool,
        open: @escaping (ModelConfiguration) throws -> ModelContainer,
    ) -> ModelContainer {
        if inMemory {
            return makeContainer(configuration: inMemoryConfiguration(), opens: [open])
        }
        return makeContainer(
            configuration: ModelConfiguration(schema: schema, isStoredInMemoryOnly: false),
            opens: [open, open],
        )
    }

    /// Tries each of `opens` in order and returns the first container that
    /// opens; with none, marks the store unavailable and returns an in-memory one.
    @MainActor
    static func makeContainer(
        configuration: ModelConfiguration,
        opens: [(ModelConfiguration) throws -> ModelContainer],
    ) -> ModelContainer {
        isPersistentStoreAvailable = true
        for (index, open) in opens.enumerated() {
            do {
                return try open(configuration)
            } catch {
                logStoreOpenFailure(error, retrying: index < opens.count - 1)
            }
        }

        isPersistentStoreAvailable = false
        let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
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
    private static var productionOpens: [(ModelConfiguration) throws -> ModelContainer] {
        [openWithMigrationPlan, openWithoutMigrationPlan]
    }

    private static func openWithMigrationPlan(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, migrationPlan: ShoutKitMigrationPlan.self, configurations: [configuration])
    }

    private static func openWithoutMigrationPlan(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func inMemoryConfiguration() -> ModelConfiguration {
        ModelConfiguration(
            "ShoutKitInMemory-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
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
