import Foundation
import SwiftData

// MARK: - Connection prewarm candidates

public extension LibraryStore {
    /// Stream URLs for the stations the user is most likely to play next —
    /// favorites (in their manual order) followed by the most-played recents —
    /// deduplicated and capped at `limit`. Used to prewarm network connections
    /// at launch so the first tap starts faster. Returns only stations that
    /// carry a snapshotted stream URL (no directory round-trip needed to warm).
    func prewarmStreamURLs(limit: Int) -> [URL] {
        guard limit > 0 else { return [] }

        var urls: [URL] = []
        var seen = Set<String>()
        func appendURL(from string: String?) {
            guard urls.count < limit,
                  let string,
                  seen.insert(string).inserted,
                  let url = URL(string: string) else { return }
            urls.append(url)
        }

        let favoritesDescriptor = FetchDescriptor<FavoriteStation>(
            sortBy: [SortDescriptor(\.sortIndex, order: .forward)]
        )
        for favorite in fetch(favoritesDescriptor, operation: "prewarm favorites") ?? [] {
            appendURL(from: favorite.streamURLString)
        }

        var recentsDescriptor = FetchDescriptor<RecentStation>(
            sortBy: [
                SortDescriptor(\.playCount, order: .reverse),
                SortDescriptor(\.playedAt, order: .reverse)
            ]
        )
        recentsDescriptor.fetchLimit = limit
        for recent in fetch(recentsDescriptor, operation: "prewarm recents") ?? [] {
            appendURL(from: recent.streamURLString)
        }

        return urls
    }
}
