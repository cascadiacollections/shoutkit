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
    public static let recentlyHeardLimit = 250
    /// Fetch/deletion headroom for bounded-history trimming; deleting in batches
    /// avoids churn from trimming on every insert near the cap.
    public static let recentlyHeardTrimHeadroom = 100

    /// Station IDs the user has favorited. Kept in sync with the persistent store so
    /// SwiftUI views observing this store update immediately on toggle.
    public private(set) var favoriteIDs: Set<String> = []
    public private(set) var lastErrorMessage: String?

    @ObservationIgnored private let context: ModelContext
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

        var reordered = favorites
        reordered.move(fromOffsets: source, toOffset: destination)

        for (index, favorite) in reordered.enumerated() where favorite.sortIndex != index {
            favorite.sortIndex = index
        }
        save(operation: "move favorites")
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

    /// Stations the user is most likely to play next —
    /// favorites (in their manual order) followed by the most-played recents —
    /// deduplicated and capped at `limit`. CarPlay and other browse surfaces use
    /// this shared ordering so the user's strongest signals appear first.
    public func rankedStations(limit: Int) -> [Station] {
        guard limit > 0 else { return [] }
        return Array(rankedStationCandidates().prefix(limit))
    }

    /// Stream URLs for the stations the user is most likely to play next —
    /// favorites (in their manual order) followed by the most-played recents —
    /// deduplicated and capped at `limit`. Used to prewarm network connections
    /// at launch so the first tap starts faster. Returns only stations that
    /// carry a snapshotted stream URL (no directory round-trip needed to warm).
    public func prewarmStreamURLs(limit: Int) -> [URL] {
        guard limit > 0 else { return [] }

        var urls: [URL] = []
        var seen = Set<String>()
        func appendURL(from url: URL?) {
            guard urls.count < limit,
                  let url,
                  seen.insert(url.absoluteString).inserted else { return }
            urls.append(url)
        }

        for station in rankedStationCandidates() {
            appendURL(from: station.preferredStreamURL)
        }

        return urls
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
        var descriptor = FetchDescriptor<RecentStation>(
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.recentsLimit + 50

        guard let recents = fetch(descriptor, operation: "trim recents"), recents.count > Self.recentsLimit else {
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

        var singleTrackDescriptor = FetchDescriptor<RecentlyHeardTrack>(
            sortBy: [SortDescriptor(\.heardAt, order: .reverse)]
        )
        singleTrackDescriptor.fetchLimit = 1

        if let latest = try? context.fetch(singleTrackDescriptor).first,
           latest.stationID == station.id,
           latest.title == title,
           latest.artist == artist {
            // Consecutive dedupe keeps one row but refreshes its timestamp so it
            // reflects the most recent hearing of that still-current track.
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
        save(operation: "log recently heard track \(sanitizedForLogs(station.id))")
    }

    private func trimRecentlyHeardTracks() {
        var trimDescriptor = FetchDescriptor<RecentlyHeardTrack>(
            sortBy: [SortDescriptor(\.heardAt, order: .reverse)]
        )
        trimDescriptor.fetchLimit = Self.recentlyHeardLimit + Self.recentlyHeardTrimHeadroom

        guard let tracks = try? context.fetch(trimDescriptor), tracks.count > Self.recentlyHeardLimit else {
            return
        }

        for stale in tracks[Self.recentlyHeardLimit...] {
            context.delete(stale)
        }
    }

    private func rankedStationCandidates() -> [Station] {
        var stations: [Station] = []
        var seenStationIDs = Set<String>()

        func append(_ station: Station) {
            guard seenStationIDs.insert(station.id).inserted else { return }
            stations.append(station)
        }

        let favoritesDescriptor = FetchDescriptor<FavoriteStation>(
            sortBy: [SortDescriptor(\.sortIndex, order: .forward)]
        )
        for favorite in fetch(favoritesDescriptor, operation: "rank favorites") ?? [] {
            append(favorite.station)
        }

        let recentsDescriptor = FetchDescriptor<RecentStation>(
            sortBy: [
                SortDescriptor(\.playCount, order: .reverse),
                SortDescriptor(\.playedAt, order: .reverse)
            ]
        )
        for recent in fetch(recentsDescriptor, operation: "rank recents") ?? [] {
            append(recent.station)
        }

        return stations
    }

    // MARK: - Helpers

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

        for (index, favorite) in favorites.enumerated() {
            favorite.sortIndex = index
        }
        save(operation: "normalize sort indices")
    }

    private func fetch<Model>(
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
    private func save(operation: String) -> Bool {
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

    private func sanitizedForLogs(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }
}
