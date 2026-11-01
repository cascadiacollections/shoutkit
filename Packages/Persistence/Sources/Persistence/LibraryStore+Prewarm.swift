import Foundation
import RadioDirectory
import SwiftData

// MARK: - Ranked stations and connection prewarm candidates

public extension LibraryStore {
    /// The newest played station snapshot, or `nil` when the user has no recent
    /// history yet. Uses the persisted `RecentStation` row so callers get the
    /// same stream/artwork snapshot playback and App Intents already rely on.
    func mostRecentStation() -> Station? {
        var descriptor = FetchDescriptor<RecentStation>(
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)],
        )
        descriptor.fetchLimit = 1
        return fetch(descriptor, operation: "fetch most recent station")?.first?.station
    }

    /// Favorites in their persisted display order. Used by background refresh to
    /// re-resolve snapshotted stream URLs without disturbing the user's manual
    /// arrangement.
    func favoriteStations() -> [Station] {
        let descriptor = FetchDescriptor<FavoriteStation>(
            sortBy: [SortDescriptor(\.sortIndex, order: .forward)],
        )
        return (fetch(descriptor, operation: "fetch favorite stations") ?? []).map(\.station)
    }

    /// Refreshes the persisted stream-URL snapshot for a station everywhere it is
    /// stored so playback/prewarm can use the newer endpoint on the next launch.
    func refreshStreamURLSnapshot(stationID: String, streamURL: URL) {
        let streamURLString = streamURL.absoluteString
        var didChange = false

        let favoritePredicate = #Predicate<FavoriteStation> { $0.stationID == stationID }
        let favoriteDescriptor = FetchDescriptor<FavoriteStation>(predicate: favoritePredicate)
        for favorite in fetch(
            favoriteDescriptor,
            operation: "refresh favorite stream URL \(sanitizedForLogs(stationID))",
        ) ?? [] where favorite.streamURLString != streamURLString {
            favorite.streamURLString = streamURLString
            didChange = true
        }

        let recentPredicate = #Predicate<RecentStation> { $0.stationID == stationID }
        let recentDescriptor = FetchDescriptor<RecentStation>(predicate: recentPredicate)
        for recent in fetch(
            recentDescriptor,
            operation: "refresh recent stream URL \(sanitizedForLogs(stationID))",
        ) ?? [] where recent.streamURLString != streamURLString {
            recent.streamURLString = streamURLString
            didChange = true
        }

        if didChange {
            save(operation: "refresh stream URL snapshot \(sanitizedForLogs(stationID))")
        }
    }

    /// Stations the user is most likely to play next —
    /// favorites (in their manual order) followed by the most-played recents —
    /// deduplicated and capped at `limit`. CarPlay and other browse surfaces use
    /// this shared ordering so the user's strongest signals appear first.
    func rankedStations(limit: Int) -> [Station] {
        guard limit > 0 else { return [] }
        return collectRankedStations(limit: limit, requireStreamURL: false)
    }

    /// Stream URLs for the stations the user is most likely to play next —
    /// favorites (in their manual order) followed by the most-played recents —
    /// deduplicated and capped at `limit`. Used to prewarm network connections
    /// at launch so the first tap starts faster. Returns only stations that
    /// carry a snapshotted stream URL (no directory round-trip needed to warm).
    func prewarmStreamURLs(limit: Int) -> [URL] {
        guard limit > 0 else { return [] }
        return collectRankedStations(limit: limit, requireStreamURL: true).compactMap(\.preferredStreamURL)
    }
}

extension LibraryStore {
    /// Favorites (`sortIndex` ascending), then recents (play count, then recency).
    /// Reads only as far as `limit` accepted stations. Favorites are uncapped, and
    /// CarPlay calls ``rankedStations(limit:)`` on every station change, so the
    /// walk is paged instead of materializing the whole table and then dropping
    /// the tail.
    ///
    /// `requireStreamURL` is the prewarm rule: a station with no snapshot URL, or
    /// one whose URL was already accepted, does not count toward `limit` and does
    /// not end the walk. Ranked stations count every new station id, URL or not.
    private func collectRankedStations(limit: Int, requireStreamURL: Bool) -> [Station] {
        var accepted: [Station] = []
        var seenStationIDs = Set<String>()
        var seenURLs = Set<String>()

        func accept(_ station: Station) -> Bool {
            guard seenStationIDs.insert(station.id).inserted else { return false }
            if requireStreamURL {
                guard let url = station.preferredStreamURL,
                      seenURLs.insert(url.absoluteString).inserted else { return false }
            }
            accepted.append(station)
            return accepted.count == limit
        }

        let favorites = FetchDescriptor<FavoriteStation>(
            sortBy: [SortDescriptor(\.sortIndex, order: .forward)],
        )
        visitRankedPages(favorites, pageSize: limit, operation: "rank favorites") { favorite in
            accept(favorite.station)
        }
        if accepted.count == limit {
            return accepted
        }

        let recents = FetchDescriptor<RecentStation>(
            sortBy: [
                SortDescriptor(\.playCount, order: .reverse),
                SortDescriptor(\.playedAt, order: .reverse),
            ],
        )
        visitRankedPages(recents, pageSize: limit, operation: "rank recents") { recent in
            accept(recent.station)
        }
        return accepted
    }

    /// Grows `fetchLimit` until the visitor stops or the table runs out. Each
    /// larger page is walked from the start; callers ignore rows they have
    /// already accepted, so a sort that is only stable inside one fetch cannot
    /// skip a row. A page that doesn't grow ends the source, including a fetch
    /// that ignores `fetchLimit`. A failed page ends this source only — the
    /// caller continues with the next one, matching the old `?? []` fetch.
    private func visitRankedPages<Model: PersistentModel>(
        _ descriptor: FetchDescriptor<Model>,
        pageSize: Int,
        operation: String,
        _ visit: (Model) -> Bool,
    ) {
        var fetched = 0
        var window = pageSize
        while true {
            var page = descriptor
            page.fetchLimit = window
            guard let batch = fetch(page, operation: operation) else { return }
            if batch.count <= fetched {
                return
            }
            for model in batch where visit(model) {
                return
            }
            if batch.count < window {
                return
            }
            fetched = batch.count
            window += pageSize
        }
    }
}
