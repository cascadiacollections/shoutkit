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
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return fetch(descriptor, operation: "fetch most recent station")?.first?.station
    }

    /// Favorites in their persisted display order. Used by background refresh to
    /// re-resolve snapshotted stream URLs without disturbing the user's manual
    /// arrangement.
    func favoriteStations() -> [Station] {
        let descriptor = FetchDescriptor<FavoriteStation>(
            sortBy: [SortDescriptor(\.sortIndex, order: .forward)]
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
            operation: "refresh favorite stream URL \(sanitizedForLogs(stationID))"
        ) ?? [] where favorite.streamURLString != streamURLString {
            favorite.streamURLString = streamURLString
            didChange = true
        }

        let recentPredicate = #Predicate<RecentStation> { $0.stationID == stationID }
        let recentDescriptor = FetchDescriptor<RecentStation>(predicate: recentPredicate)
        for recent in fetch(
            recentDescriptor,
            operation: "refresh recent stream URL \(sanitizedForLogs(stationID))"
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
        return Array(rankedStationCandidates().prefix(limit))
    }

    /// Stream URLs for the stations the user is most likely to play next —
    /// favorites (in their manual order) followed by the most-played recents —
    /// deduplicated and capped at `limit`. Used to prewarm network connections
    /// at launch so the first tap starts faster. Returns only stations that
    /// carry a snapshotted stream URL (no directory round-trip needed to warm).
    func prewarmStreamURLs(limit: Int) -> [URL] {
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
}

extension LibraryStore {
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
}
