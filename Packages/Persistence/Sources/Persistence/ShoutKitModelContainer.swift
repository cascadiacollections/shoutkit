import Foundation
import SwiftData
#if canImport(OSLog)
import OSLog
#endif

public enum ShoutKitModelContainer {
    /// The SwiftData schema backing favorites, recents, and recently heard tracks.
    public static let schema = Schema([
        FavoriteStation.self,
        RecentStation.self,
        RecentlyHeardTrack.self
    ])

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
        makeContainer(inMemory: inMemory) { configuration in
            try ModelContainer(for: schema, configurations: [configuration])
        }
    }

    @MainActor
    static func makeContainer(
        inMemory: Bool,
        open: (ModelConfiguration) throws -> ModelContainer
    ) -> ModelContainer {
        isPersistentStoreAvailable = true
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )

        let attempts = inMemory ? 1 : 2
        for attempt in 1...attempts {
            do {
                return try open(configuration)
            } catch {
                let retrying = attempt < attempts
                logStoreOpenFailure(error, retrying: retrying)
            }
        }

        isPersistentStoreAvailable = false
        let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // Last-resort in-memory container keeps the app usable if disk fails;
        // in-memory construction has no failure mode worth surviving past.
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: schema, configurations: [fallback])
    }

    private static func logStoreOpenFailure(_ error: Error, retrying: Bool) {
        let message = if retrying {
            "Failed to open persistent SwiftData store; retrying once before fallback: \(error)"
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
