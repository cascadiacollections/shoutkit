import Foundation
import Testing

@testable import LibraryFeatureCore

struct LibraryListEditingTests {
    @Test func recentDeletionOnlyUsesDisplayedSlice() {
        let recents = (1...20).map { "station-\($0)" }

        let stationIDs = LibraryListEditing.stationIDsForRecentDeletion(
            recentStationIDsNewestFirst: recents,
            offsets: IndexSet([0, 14, 15])
        )

        #expect(stationIDs == ["station-1", "station-15"])
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
