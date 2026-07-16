import Testing

@testable import Persistence

struct RecentlyPlayedTeaserStateTests {
    @Test func firstSyncSeedsUpToCapacity() {
        var teaser = RecentlyPlayedTeaserState(capacity: 5)

        teaser.sync(withVisibleIDsNewestFirst: ["a", "b", "c", "d", "e", "f", "g"])

        #expect(teaser.displayedIDs == ["a", "b", "c", "d", "e"])
    }

    @Test func firstSyncWithFewerThanCapacityShowsAllOfThem() {
        var teaser = RecentlyPlayedTeaserState(capacity: 5)

        teaser.sync(withVisibleIDsNewestFirst: ["a", "b"])

        #expect(teaser.displayedIDs == ["a", "b"])
    }

    @Test func removingAnEntryShrinksTheListWithoutBackfill() {
        var teaser = RecentlyPlayedTeaserState(capacity: 5)
        teaser.sync(withVisibleIDsNewestFirst: ["a", "b", "c", "d", "e", "f"])

        teaser.remove("c")

        // "f" exists in history but must NOT backfill the freed slot.
        #expect(teaser.displayedIDs == ["a", "b", "d", "e"])

        // A subsequent sync against the same (still-visible) history must not
        // resurrect or backfill the removed/absent slot either.
        teaser.sync(withVisibleIDsNewestFirst: ["a", "b", "c", "d", "e", "f"])
        #expect(teaser.displayedIDs == ["a", "b", "d", "e"])
    }

    @Test func newTopPlayPromotesAndTrimsOldestOverCapacity() {
        var teaser = RecentlyPlayedTeaserState(capacity: 5)
        teaser.sync(withVisibleIDsNewestFirst: ["a", "b", "c", "d", "e"])

        // "z" is a brand-new play, landing at the top of history.
        teaser.sync(withVisibleIDsNewestFirst: ["z", "a", "b", "c", "d", "e"])

        #expect(teaser.displayedIDs == ["z", "a", "b", "c", "d"])
    }

    @Test func replayingAnAlreadyDisplayedStationMovesItToFrontWithoutDuplicating() {
        var teaser = RecentlyPlayedTeaserState(capacity: 5)
        teaser.sync(withVisibleIDsNewestFirst: ["a", "b", "c"])

        // "c" is played again, becoming the new top of history.
        teaser.sync(withVisibleIDsNewestFirst: ["c", "a", "b"])

        #expect(teaser.displayedIDs == ["c", "a", "b"])
    }

    @Test func emptyHistoryClearsTheTeaser() {
        var teaser = RecentlyPlayedTeaserState(capacity: 5)
        teaser.sync(withVisibleIDsNewestFirst: ["a", "b"])

        teaser.sync(withVisibleIDsNewestFirst: [])

        #expect(teaser.displayedIDs.isEmpty)
    }

    @Test func syncWithUnchangedTopIsANoOp() {
        var teaser = RecentlyPlayedTeaserState(capacity: 5)
        teaser.sync(withVisibleIDsNewestFirst: ["a", "b", "c", "d", "e", "f"])
        let before = teaser.displayedIDs

        // Same top ("a"); a new play elsewhere in history further down must not
        // reshuffle the already-seeded teaser.
        teaser.sync(withVisibleIDsNewestFirst: ["a", "z", "b", "c", "d", "e", "f"])

        #expect(teaser.displayedIDs == before)
    }

    // MARK: - restore (undo)

    @Test func restoreReinsertsAtTheGivenIndex() {
        var teaser = RecentlyPlayedTeaserState(capacity: 5)
        teaser.sync(withVisibleIDsNewestFirst: ["a", "b", "c", "d"])
        teaser.remove("b")

        teaser.restore("b", at: 1)

        #expect(teaser.displayedIDs == ["a", "b", "c", "d"])
    }

    @Test func restoreClampsAnOutOfRangeIndexToTheEnd() {
        var teaser = RecentlyPlayedTeaserState(capacity: 5)
        teaser.sync(withVisibleIDsNewestFirst: ["a", "b"])
        teaser.remove("b")

        teaser.restore("b", at: 99)

        #expect(teaser.displayedIDs == ["a", "b"])
    }

    @Test func restoreIsANoOpWhenTheIDIsAlreadyDisplayed() {
        var teaser = RecentlyPlayedTeaserState(capacity: 5)
        teaser.sync(withVisibleIDsNewestFirst: ["a", "b"])

        teaser.restore("a", at: 0)

        #expect(teaser.displayedIDs == ["a", "b"])
    }

    @Test func restoreReTrimsToCapacityIfANewPlayFilledTheSlotMeanwhile() {
        var teaser = RecentlyPlayedTeaserState(capacity: 3)
        teaser.sync(withVisibleIDsNewestFirst: ["a", "b", "c"])
        teaser.remove("b")
        // A brand-new play lands at the top while "b" is dismissed.
        teaser.sync(withVisibleIDsNewestFirst: ["z", "a", "c"])
        #expect(teaser.displayedIDs == ["z", "a", "c"])

        teaser.restore("b", at: 1)

        // Restoring "b" would overflow capacity 3; the oldest entry ("c") is
        // trimmed rather than "b" silently failing to reappear.
        #expect(teaser.displayedIDs == ["z", "b", "a"])
    }
}
