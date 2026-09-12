import Foundation

/// Offset-to-identity resolution for the library's editable lists.
///
/// `onDelete` hands back positions in the *rendered* list, and the view renders
/// live SwiftData queries. Resolving every position to a station ID up front —
/// against the same slice the rows were built from — is what keeps a multi-row
/// delete from removing the wrong station once the first removal shifts the
/// query result underneath it.
public enum LibraryListEditing {
    /// How many recents the library renders. The view slices with this, and the
    /// deletion mapping below slices with it too — they must agree, or an
    /// offset resolves against a longer list than the one the rows came from.
    public static let recentDisplayLimit = 15

    public static func stationIDsForRecentDeletion(
        recentStationIDsNewestFirst: [String],
        offsets: IndexSet,
        displayLimit: Int = recentDisplayLimit,
    ) -> [String] {
        stationIDsForDeletion(
            in: Array(recentStationIDsNewestFirst.prefix(Swift.max(displayLimit, 0))),
            offsets: offsets,
        )
    }

    public static func stationIDsForFavoriteDeletion(
        favoriteStationIDs: [String],
        offsets: IndexSet,
    ) -> [String] {
        stationIDsForDeletion(in: favoriteStationIDs, offsets: offsets)
    }

    /// Out-of-range offsets are dropped rather than trapped: the rendered list
    /// and the live query can disagree for a frame (a station removed on the
    /// watch, a recent aged out mid-gesture), and a stale offset should cost
    /// the deletion, not the process.
    private static func stationIDsForDeletion(in stationIDs: [String], offsets: IndexSet) -> [String] {
        offsets.compactMap { offset in
            guard stationIDs.indices.contains(offset) else { return nil }
            return stationIDs[offset]
        }
    }
}
