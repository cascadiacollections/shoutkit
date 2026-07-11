import Foundation
import SwiftData

public enum ShoutKitModelContainer {
    /// The SwiftData schema backing favorites, recents, and recently heard tracks.
    public static let schema = Schema([
        FavoriteStation.self,
        RecentStation.self,
        RecentlyHeardTrack.self
    ])

    /// Builds the app-wide persistent container. Falls back to an in-memory
    /// store if the on-disk store cannot be opened so the UI still functions.
    @MainActor
    public static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // Last-resort in-memory container keeps the app usable if disk fails;
            // in-memory construction has no failure mode worth surviving past.
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }
}
