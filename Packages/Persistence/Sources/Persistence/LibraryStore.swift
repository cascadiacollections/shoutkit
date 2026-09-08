import Foundation
import Observation
import OSLog
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
    /// Raised from 250 (2026-08-20, see DECISIONS.md): the Top Tracks report
    /// aggregates over this same table, and 250 rows total across every
    /// station was too shallow a window to answer "most played this week/month"
    /// once a listener has more than a handful of repeats. Rows are tiny
    /// (two strings, two optional URLs, a date), so 4x the retention is cheap.
    public static let recentlyHeardLimit = 1000
    static let recentsTrimHeadroom = 50
    /// Fetch/deletion headroom for bounded-history trimming batches. Repeated
    /// passes ensure deep backlogs are fully drained while keeping each fetch
    /// bounded.
    public static let recentlyHeardTrimHeadroom = 100

    /// Station IDs the user has favorited. Kept in sync with the persistent store so
    /// SwiftUI views observing this store update immediately on toggle.
    public private(set) var favoriteIDs: Set<String> = []
    public private(set) var lastErrorMessage: String?

    // `context` and the fetch/save/log helpers below are module-internal (not
    // private) so the same-module extension files (LibraryStore+Prewarm,
    // LibraryStore+RecentlyHeard) can share the persistence plumbing.
    @ObservationIgnored let context: ModelContext
    @ObservationIgnored private let logger = Logger(subsystem: "ShoutKit.Persistence", category: "LibraryStore")

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
        save(operation: "add favorite \(sanitizedForLogs(station.id))")
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

        let orderedDescriptor = FetchDescriptor<FavoriteStation>(
            sortBy: [SortDescriptor(\.sortIndex, order: .forward)]
        )
        guard let persistedFavorites = fetch(orderedDescriptor, operation: "load favorites for move") else {
            return
        }
        guard persistedFavorites.count == favorites.count,
              zip(persistedFavorites, favorites).allSatisfy({ $0.stationID == $1.stationID }) else {
            logger.warning(
                """
                move favorites skipped due to source mismatch \
                [persistedCount: \(persistedFavorites.count), passedCount: \(favorites.count)]
                """
            )
            return
        }

        var reordered = persistedFavorites
        reordered.move(fromOffsets: source, toOffset: destination)

        for (index, favorite) in reordered.enumerated() where favorite.sortIndex != index {
            favorite.sortIndex = index
        }
        save(operation: "move favorites")
    }

    /// Favorites in the user's display order (`sortIndex` ascending) — the same
    /// order the Favorites tab's `@Query` and the quick-play widget snapshot
    /// use. For callers that mutate favorites outside a SwiftUI scene (App
    /// Intents, background work) and need the list to republish.
    public func orderedFavorites() -> [FavoriteStation] {
        let descriptor = FetchDescriptor<FavoriteStation>(
            sortBy: [SortDescriptor(\.sortIndex, order: .forward)]
        )
        return fetch(descriptor, operation: "fetch ordered favorites") ?? []
    }

    /// The next ordering slot, one past the current maximum, so new favorites append
    /// to the bottom of the user's arrangement.
    private func nextSortIndex() -> Int {
        var descriptor = FetchDescriptor<FavoriteStation>(
            sortBy: [SortDescriptor(\.sortIndex, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let maxIndex = fetch(descriptor, operation: "compute next sort index")?.first?.sortIndex
        return (maxIndex ?? -1) + 1
    }

    public func removeFavorite(stationID: String) {
        let predicate = #Predicate<FavoriteStation> { $0.stationID == stationID }
        let descriptor = FetchDescriptor<FavoriteStation>(predicate: predicate)

        guard let matches = fetch(descriptor, operation: "remove favorite \(sanitizedForLogs(stationID))") else {
            return
        }

        for match in matches {
            context.delete(match)
        }
        favoriteIDs.remove(stationID)
        save(operation: "remove favorite \(sanitizedForLogs(stationID))")
    }

    // MARK: - Recents

    /// Records a play. De-duplicates by station and trims to `recentsLimit`.
    public func logRecent(_ station: Station) {
        let stationID = station.id
        let predicate = #Predicate<RecentStation> { $0.stationID == stationID }
        let descriptor = FetchDescriptor<RecentStation>(predicate: predicate)

        guard let matches = fetch(descriptor, operation: "log recent \(sanitizedForLogs(stationID))") else {
            return
        }

        if let existing = matches.first {
            existing.playedAt = .now
            existing.playCount += 1
            // A genuine new play un-hides it from Listen Now even if it was
            // previously dismissed there.
            existing.isHiddenFromListenNow = false
            existing.name = station.name
            existing.genre = station.genre
            existing.tagsCSV = Station.tagsCSV(from: station.tags)
            existing.country = station.country
            existing.codec = station.codec
            existing.language = station.language
            existing.clickTrend = station.clickTrend
            existing.votes = station.votes
            existing.bitrate = station.bitrate
            existing.artworkURLString = station.artworkURL?.absoluteString
            existing.streamURLString = station.preferredStreamURL?.absoluteString
        } else {
            let recent = RecentStation(
                stationID: station.id,
                name: station.name,
                genre: station.genre,
                tagsCSV: Station.tagsCSV(from: station.tags),
                country: station.country,
                codec: station.codec,
                language: station.language,
                clickTrend: station.clickTrend,
                votes: station.votes,
                bitrate: station.bitrate,
                artworkURLString: station.artworkURL?.absoluteString,
                streamURLString: station.preferredStreamURL?.absoluteString
            )
            context.insert(recent)
        }

        trimRecents()
        save(operation: "log recent \(sanitizedForLogs(stationID))")
    }

    /// Removes a single entry from the recently played history by station ID.
    public func removeRecent(stationID: String) {
        let predicate = #Predicate<RecentStation> { $0.stationID == stationID }
        let descriptor = FetchDescriptor<RecentStation>(predicate: predicate)

        guard let matches = fetch(descriptor, operation: "remove recent \(sanitizedForLogs(stationID))") else {
            return
        }

        for match in matches {
            context.delete(match)
        }
        save(operation: "remove recent \(sanitizedForLogs(stationID))")
    }

    /// Dismisses a single entry from the Listen Now "Recently Played" teaser
    /// without deleting its play record, so recommendation scoring (which
    /// reads the full, unfiltered history) is unaffected.
    public func hideFromListenNow(stationID: String) {
        setHiddenFromListenNow(true, stationID: stationID)
    }

    /// Reverses `hideFromListenNow` — powers the "Undo" action on a Listen Now
    /// dismiss.
    public func unhideFromListenNow(stationID: String) {
        setHiddenFromListenNow(false, stationID: stationID)
    }

    private func setHiddenFromListenNow(_ isHidden: Bool, stationID: String) {
        let predicate = #Predicate<RecentStation> { $0.stationID == stationID }
        let descriptor = FetchDescriptor<RecentStation>(predicate: predicate)
        let operation = "\(isHidden ? "hide from" : "unhide from") listen now \(sanitizedForLogs(stationID))"

        guard let matches = fetch(descriptor, operation: operation) else {
            return
        }

        for match in matches {
            match.isHiddenFromListenNow = isHidden
        }
        save(operation: operation)
    }

    private func trimRecents() {
        let fetchLimit = Self.recentsLimit + Self.recentsTrimHeadroom
        var shouldContinue = true
        while shouldContinue {
            var descriptor = FetchDescriptor<RecentStation>(
                sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
            )
            descriptor.fetchLimit = fetchLimit

            guard let recents = fetch(descriptor, operation: "trim recents"), recents.count > Self.recentsLimit else {
                return
            }

            for stale in recents[Self.recentsLimit...] {
                context.delete(stale)
            }

            shouldContinue = recents.count == fetchLimit
            if shouldContinue, save(operation: "trim recents batch") == false {
                return
            }
        }
    }
}

// MARK: - Helpers

extension LibraryStore {
    private func reloadFavoriteIDs() {
        let descriptor = FetchDescriptor<FavoriteStation>()
        guard let favorites = fetch(descriptor, operation: "reload favorites") else {
            favoriteIDs = []
            return
        }

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
        guard let favorites = fetch(descriptor, operation: "normalize sort indices"),
              favorites.count > 1 else { return }

        let indices = favorites.map(\.sortIndex)
        guard Set(indices).count != indices.count else { return }
        let hasAllZeroIndices = indices.allSatisfy({ $0 == 0 })
        guard hasAllZeroIndices else { return }

        for (index, favorite) in favorites.enumerated() {
            favorite.sortIndex = index
        }
        save(operation: "normalize sort indices")
    }

    func fetch<Model>(
        _ descriptor: FetchDescriptor<Model>,
        operation: String
    ) -> [Model]? where Model: PersistentModel {
        do {
            let models = try context.fetch(descriptor)
            lastErrorMessage = nil
            return models
        } catch {
            record(error, operation: operation)
            return nil
        }
    }

    @discardableResult
    func save(operation: String) -> Bool {
        do {
            try context.save()
            lastErrorMessage = nil
            return true
        } catch {
            context.rollback()
            reloadFavoriteIDs()
            record(error, operation: operation)
            return false
        }
    }

    private func record(_ error: Error, operation: String) {
        let localizedMessage = error.localizedDescription
        let debugDescription = String(describing: error)
        lastErrorMessage = localizedMessage
        logger.error(
            """
            LibraryStore \(operation, privacy: .public) failed: \
            \(localizedMessage, privacy: .public) [\(debugDescription, privacy: .public)]
            """
        )
    }

    func sanitizedForLogs(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }
}
