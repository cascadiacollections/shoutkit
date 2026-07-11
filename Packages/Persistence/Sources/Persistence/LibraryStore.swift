import Foundation
import Observation
import RadioDirectory
import SwiftData

/// App-wide store for user library state (favorites, recents, recently heard),
/// backed by SwiftData.
///
/// Views can read `favoriteIDs` reactively for instant heart-toggle feedback, while
/// the `FavoriteStation` / `RecentStation` models remain queryable via `@Query`.
@MainActor
@Observable
public final class LibraryStore {
    public static let recentsLimit = 25
    public static let recentlyHeardLimit = 250
    /// Fetch/deletion headroom for bounded-history trimming; deleting in batches
    /// avoids churn from trimming on every insert near the cap.
    public static let recentlyHeardTrimHeadroom = 100

    /// Station IDs the user has favorited. Kept in sync with the persistent store so
    /// SwiftUI views observing this store update immediately on toggle.
    public private(set) var favoriteIDs: Set<String> = []

    @ObservationIgnored private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
        reloadFavoriteIDs()
        normalizeSortIndicesIfNeeded()
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
            streamURLString: station.preferredStreamURL?.absoluteString,
            sortIndex: nextSortIndex()
        )
        context.insert(favorite)
        favoriteIDs.insert(station.id)
        save()
    }

    /// Reorders favorites to match a SwiftUI `.onMove` drag and rewrites `sortIndex`
    /// contiguously (0..<count) so the persisted order is stable and gap-free.
    /// `favorites` must be the currently displayed rows, in display order.
    public func moveFavorites(_ favorites: [FavoriteStation], from source: IndexSet, to destination: Int) {
        // `Array.move(fromOffsets:toOffset:)` traps on out-of-range offsets. SwiftUI's
        // `.onMove` always supplies valid indices, but guard so this public API can't
        // crash on accidental misuse. An empty/invalid move is a no-op.
        let count = favorites.count
        guard let maxSource = source.max(), maxSource < count, (0...count).contains(destination) else { return }

        var reordered = favorites
        reordered.move(fromOffsets: source, toOffset: destination)

        for (index, favorite) in reordered.enumerated() where favorite.sortIndex != index {
            favorite.sortIndex = index
        }
        save()
    }

    /// The next ordering slot, one past the current maximum, so new favorites append
    /// to the bottom of the user's arrangement.
    private func nextSortIndex() -> Int {
        var descriptor = FetchDescriptor<FavoriteStation>(
            sortBy: [SortDescriptor(\.sortIndex, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let maxIndex = (try? context.fetch(descriptor))?.first?.sortIndex
        return (maxIndex ?? -1) + 1
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

    // MARK: - Recently heard tracks

    /// Records parsed now-playing metadata as local track history, de-duplicating
    /// only consecutive repeats and trimming to `recentlyHeardLimit`.
    public func logRecentlyHeardTrack(
        station: Station,
        title: String?,
        artist: String?,
        heardAt: Date = .now,
        appleMusicURL: URL? = nil
    ) {
        guard title != nil || artist != nil else { return }

        var latestDescriptor = FetchDescriptor<RecentlyHeardTrack>(
            sortBy: [SortDescriptor(\.heardAt, order: .reverse)]
        )
        latestDescriptor.fetchLimit = 1

        if let latest = try? context.fetch(latestDescriptor).first,
           latest.stationID == station.id,
           latest.title == title,
           latest.artist == artist {
            latest.stationName = station.name
            latest.heardAt = heardAt
            if let appleMusicURL {
                latest.appleMusicURLString = appleMusicURL.absoluteString
            }
        } else {
            let track = RecentlyHeardTrack(
                stationID: station.id,
                stationName: station.name,
                title: title,
                artist: artist,
                heardAt: heardAt,
                appleMusicURLString: appleMusicURL?.absoluteString
            )
            context.insert(track)
        }

        trimRecentlyHeardTracks()
        save()
    }

    private func trimRecentlyHeardTracks() {
        var descriptor = FetchDescriptor<RecentlyHeardTrack>(
            sortBy: [SortDescriptor(\.heardAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.recentlyHeardLimit + Self.recentlyHeardTrimHeadroom

        guard let tracks = try? context.fetch(descriptor), tracks.count > Self.recentlyHeardLimit else {
            return
        }

        for stale in tracks[Self.recentlyHeardLimit...] {
            context.delete(stale)
        }
    }

    // MARK: - Helpers

    private func reloadFavoriteIDs() {
        let descriptor = FetchDescriptor<FavoriteStation>()
        let favorites = (try? context.fetch(descriptor)) ?? []
        favoriteIDs = Set(favorites.map(\.stationID))
    }

    /// One-time repair after the `sortIndex` migration: pre-existing rows all migrate
    /// to `sortIndex == 0`. When duplicate indices are detected, rewrite contiguous
    /// indices following the legacy newest-first (`createdAt` descending) order so the
    /// list looks unchanged after upgrading. Distinct indices short-circuit, making
    /// this a no-op on every subsequent launch.
    private func normalizeSortIndicesIfNeeded() {
        let descriptor = FetchDescriptor<FavoriteStation>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let favorites = try? context.fetch(descriptor), favorites.count > 1 else { return }

        let indices = favorites.map(\.sortIndex)
        guard Set(indices).count != indices.count else { return }

        for (index, favorite) in favorites.enumerated() {
            favorite.sortIndex = index
        }
        save()
    }

    private func save() {
        try? context.save()
    }
}
