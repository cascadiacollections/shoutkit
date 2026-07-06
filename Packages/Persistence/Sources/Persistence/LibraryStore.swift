import Foundation
import Observation
import RadioDirectory
import SwiftData

/// App-wide store for user library state (favorites + recents), backed by SwiftData.
///
/// Views can read `favoriteIDs` reactively for instant heart-toggle feedback, while
/// the `FavoriteStation` / `RecentStation` models remain queryable via `@Query`.
@MainActor
@Observable
public final class LibraryStore {
    public static let recentsLimit = 25

    /// Station IDs the user has favorited. Kept in sync with the persistent store so
    /// SwiftUI views observing this store update immediately on toggle.
    public private(set) var favoriteIDs: Set<String> = []

    @ObservationIgnored private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
        reloadFavoriteIDs()
    }

    // MARK: - Favorites

    public func isFavorite(_ station: Station) -> Bool {
        favoriteIDs.contains(station.id)
    }

    public func isFavorite(stationID: String) -> Bool {
        favoriteIDs.contains(stationID)
    }

    @discardableResult
    public func toggleFavorite(_ station: Station) -> Bool {
        if isFavorite(station) {
            removeFavorite(stationID: station.id)
            return false
        } else {
            addFavorite(station)
            return true
        }
    }

    public func addFavorite(_ station: Station) {
        guard favoriteIDs.contains(station.id) == false else { return }

        let favorite = FavoriteStation(
            stationID: station.id,
            name: station.name,
            genre: station.genre,
            artworkURLString: station.artworkURL?.absoluteString,
            streamURLString: station.preferredStreamURL?.absoluteString
        )
        context.insert(favorite)
        favoriteIDs.insert(station.id)
        save()
    }

    public func removeFavorite(stationID: String) {
        let predicate = #Predicate<FavoriteStation> { $0.stationID == stationID }
        let descriptor = FetchDescriptor<FavoriteStation>(predicate: predicate)

        if let matches = try? context.fetch(descriptor) {
            for match in matches {
                context.delete(match)
            }
        }
        favoriteIDs.remove(stationID)
        save()
    }

    // MARK: - Recents

    /// Records a play. De-duplicates by station and trims to `recentsLimit`.
    public func logRecent(_ station: Station) {
        let stationID = station.id
        let predicate = #Predicate<RecentStation> { $0.stationID == stationID }
        let descriptor = FetchDescriptor<RecentStation>(predicate: predicate)

        if let existing = try? context.fetch(descriptor).first {
            existing.playedAt = .now
            existing.name = station.name
            existing.genre = station.genre
            existing.artworkURLString = station.artworkURL?.absoluteString
            existing.streamURLString = station.preferredStreamURL?.absoluteString
        } else {
            let recent = RecentStation(
                stationID: station.id,
                name: station.name,
                genre: station.genre,
                artworkURLString: station.artworkURL?.absoluteString,
                streamURLString: station.preferredStreamURL?.absoluteString
            )
            context.insert(recent)
        }

        trimRecents()
        save()
    }

    private func trimRecents() {
        var descriptor = FetchDescriptor<RecentStation>(
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.recentsLimit + 50

        guard let recents = try? context.fetch(descriptor), recents.count > Self.recentsLimit else {
            return
        }

        for stale in recents[Self.recentsLimit...] {
            context.delete(stale)
        }
    }

    // MARK: - Helpers

    private func reloadFavoriteIDs() {
        let descriptor = FetchDescriptor<FavoriteStation>()
        let favorites = (try? context.fetch(descriptor)) ?? []
        favoriteIDs = Set(favorites.map(\.stationID))
    }

    private func save() {
        try? context.save()
    }
}
