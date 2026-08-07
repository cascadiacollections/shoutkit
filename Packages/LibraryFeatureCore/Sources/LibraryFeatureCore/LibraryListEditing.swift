import Foundation

public enum LibraryListEditing {
    public static let recentDisplayLimit = 15

    public static func stationIDsForRecentDeletion(
        recentStationIDsNewestFirst: [String],
        offsets: IndexSet,
        displayLimit: Int = recentDisplayLimit
    ) -> [String] {
        stationIDsForDeletion(
            in: Array(recentStationIDsNewestFirst.prefix(Swift.max(displayLimit, 0))),
            offsets: offsets
        )
    }

    public static func stationIDsForFavoriteDeletion(
        favoriteStationIDs: [String],
        offsets: IndexSet
    ) -> [String] {
        stationIDsForDeletion(in: favoriteStationIDs, offsets: offsets)
    }

    private static func stationIDsForDeletion(in stationIDs: [String], offsets: IndexSet) -> [String] {
        offsets.compactMap { offset in
            guard stationIDs.indices.contains(offset) else { return nil }
            return stationIDs[offset]
        }
    }
}
