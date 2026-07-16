import Foundation
import RadioDirectory
import SwiftData

// MARK: - Ranked stations and connection prewarm candidates

public extension LibraryStore {
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
