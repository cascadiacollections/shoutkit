import Foundation
import Testing

@testable import LibraryFeatureCore

struct LibraryListEditingTests {
    @Test func recentDeletionOnlyUsesDisplayedSlice() {
        let recents = [
            "a", "b", "c", "d", "e",
            "f", "g", "h", "i", "j",
            "k", "l", "m", "n", "o",
            "p", "q", "r", "s", "t"
        ]

        let stationIDs = LibraryListEditing.stationIDsForRecentDeletion(
            recentStationIDsNewestFirst: recents,
            offsets: IndexSet([0, 14, 15])
        )

        #expect(stationIDs == ["a", "o"])
    }

    @Test func favoriteDeletionResolvesOffsetsInDisplayOrder() {
        let stationIDs = LibraryListEditing.stationIDsForFavoriteDeletion(
            favoriteStationIDs: ["a", "b", "c", "d"],
            offsets: IndexSet([3, 1])
        )

        #expect(stationIDs == ["b", "d"])
    }

    @Test func outOfBoundsOffsetsAreIgnored() {
        let stationIDs = LibraryListEditing.stationIDsForFavoriteDeletion(
            favoriteStationIDs: ["a", "b"],
            offsets: IndexSet([0, 9])
        )

        #expect(stationIDs == ["a"])
    }
}
