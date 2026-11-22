import Foundation
import SwiftData

public extension LibraryStore {
    /// Merges rows that share a station ID, leaving one favorite and one recent
    /// per station.
    ///
    /// `stationID` stopped being unique in ``ShoutKitSchemaV2``, because CloudKit
    /// does not support unique attributes. This store never inserts a second
    /// row for a station, but two devices can each add the same one before they
    /// sync, and both rows then arrive. Runs when the store is created; call it
    /// again after remote changes are merged.
    ///
    /// - Returns: The number of rows deleted.
    @discardableResult
    func mergeDuplicateStations() -> Int {
        let deleted = mergeDuplicateFavorites() + mergeDuplicateRecents()
        guard deleted > 0 else { return 0 }
        guard save(operation: "merge duplicate stations") else { return 0 }
        reloadFavoriteIDs()
        return deleted
    }

    /// Keeps the favorite highest in the user's order, then the oldest.
    private func mergeDuplicateFavorites() -> Int {
        let descriptor = FetchDescriptor<FavoriteStation>(
            sortBy: [SortDescriptor(\.sortIndex, order: .forward), SortDescriptor(\.createdAt, order: .forward)],
        )
        guard let favorites = fetch(descriptor, operation: "find duplicate favorites") else { return 0 }

        var seenIDs = Set<String>()
        var deleted = 0
        for favorite in favorites where seenIDs.insert(favorite.stationID).inserted == false {
            context.delete(favorite)
            deleted += 1
        }
        return deleted
    }

    /// Keeps the most recently played row and adds the play counts of the
    /// others to it: each row counted plays the other never saw.
    private func mergeDuplicateRecents() -> Int {
        let descriptor = FetchDescriptor<RecentStation>(
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)],
        )
        guard let recents = fetch(descriptor, operation: "find duplicate recents") else { return 0 }

        var keepers: [String: RecentStation] = [:]
        var deleted = 0
        for recent in recents {
            guard let keeper = keepers[recent.stationID] else {
                keepers[recent.stationID] = recent
                continue
            }
            keeper.playCount += recent.playCount
            context.delete(recent)
            deleted += 1
        }
        return deleted
    }
}
