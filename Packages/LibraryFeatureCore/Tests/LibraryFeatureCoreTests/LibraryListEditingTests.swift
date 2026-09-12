import Foundation
@testable import LibraryFeatureCore
import Testing

struct LibraryListEditingTests {
    @Test func `recent deletion only uses displayed slice`() {
        let recents = [
            "a", "b", "c", "d", "e",
            "f", "g", "h", "i", "j",
            "k", "l", "m", "n", "o",
            "p", "q", "r", "s", "t",
        ]

        let stationIDs = LibraryListEditing.stationIDsForRecentDeletion(
            recentStationIDsNewestFirst: recents,
            offsets: IndexSet([0, 14, 15]),
        )

        #expect(stationIDs == ["a", "o"])
    }

    @Test func `favorite deletion resolves offsets in display order`() {
        let stationIDs = LibraryListEditing.stationIDsForFavoriteDeletion(
            favoriteStationIDs: ["a", "b", "c", "d"],
            offsets: IndexSet([3, 1]),
        )

        #expect(stationIDs == ["b", "d"])
    }

    @Test func `out of bounds offsets are ignored`() {
        let stationIDs = LibraryListEditing.stationIDsForFavoriteDeletion(
            favoriteStationIDs: ["a", "b"],
            offsets: IndexSet([0, 9]),
        )

        #expect(stationIDs == ["a"])
    }
}
