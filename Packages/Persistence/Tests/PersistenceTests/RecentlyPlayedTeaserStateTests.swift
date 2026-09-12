@testable import Persistence
import Testing

struct RecentlyPlayedTeaserStateTests {
    @Test func `first sync seeds up to capacity`() {
        var teaser = RecentlyPlayedTeaserState(capacity: 5)

        teaser.sync(withVisibleIDsNewestFirst: ["a", "b", "c", "d", "e", "f", "g"])

        #expect(teaser.displayedIDs == ["a", "b", "c", "d", "e"])
    }

    @Test func `first sync with fewer than capacity shows all of them`() {
        var teaser = RecentlyPlayedTeaserState(capacity: 5)

        teaser.sync(withVisibleIDsNewestFirst: ["a", "b"])

        #expect(teaser.displayedIDs == ["a", "b"])
    }

    @Test func `removing an entry shrinks the list without backfill`() {
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

    @Test func `removing all entries does not trigger mass backfill`() {
        var teaser = RecentlyPlayedTeaserState(capacity: 5)
        teaser.sync(withVisibleIDsNewestFirst: ["a", "b", "c", "d", "e", "f"])

        for id in ["a", "b", "c", "d", "e"] {
            teaser.remove(id)
        }
        #expect(teaser.displayedIDs.isEmpty)

        teaser.sync(withVisibleIDsNewestFirst: ["a", "b", "c", "d", "e", "f"])
        #expect(teaser.displayedIDs.isEmpty)

        teaser.sync(withVisibleIDsNewestFirst: ["z", "a", "b", "c", "d", "e", "f"])
        #expect(teaser.displayedIDs == ["z"])
    }

    @Test func `new top play promotes and trims oldest over capacity`() {
        var teaser = RecentlyPlayedTeaserState(capacity: 5)
        teaser.sync(withVisibleIDsNewestFirst: ["a", "b", "c", "d", "e"])

        // "z" is a brand-new play, landing at the top of history.
        teaser.sync(withVisibleIDsNewestFirst: ["z", "a", "b", "c", "d", "e"])

        #expect(teaser.displayedIDs == ["z", "a", "b", "c", "d"])
    }

    @Test func `replaying an already displayed station moves it to front without duplicating`() {
        var teaser = RecentlyPlayedTeaserState(capacity: 5)
        teaser.sync(withVisibleIDsNewestFirst: ["a", "b", "c"])

        // "c" is played again, becoming the new top of history.
        teaser.sync(withVisibleIDsNewestFirst: ["c", "a", "b"])

        #expect(teaser.displayedIDs == ["c", "a", "b"])
    }

    @Test func `empty history clears the teaser`() {
        var teaser = RecentlyPlayedTeaserState(capacity: 5)
        teaser.sync(withVisibleIDsNewestFirst: ["a", "b"])

        teaser.sync(withVisibleIDsNewestFirst: [])

        #expect(teaser.displayedIDs.isEmpty)
    }

    @Test func `sync with unchanged top is A no op`() {
        var teaser = RecentlyPlayedTeaserState(capacity: 5)
        teaser.sync(withVisibleIDsNewestFirst: ["a", "b", "c", "d", "e", "f"])
        let before = teaser.displayedIDs

        // Same top ("a"); a new play elsewhere in history further down must not
        // reshuffle the already-seeded teaser.
        teaser.sync(withVisibleIDsNewestFirst: ["a", "z", "b", "c", "d", "e", "f"])

        #expect(teaser.displayedIDs == before)
    }

    // MARK: - restore (undo)

    @Test func `restore reinserts at the given index`() {
        var teaser = RecentlyPlayedTeaserState(capacity: 5)
        teaser.sync(withVisibleIDsNewestFirst: ["a", "b", "c", "d"])
        teaser.remove("b")

        teaser.restore("b", at: 1)

        #expect(teaser.displayedIDs == ["a", "b", "c", "d"])
    }

    @Test func `restore clamps an out of range index to the end`() {
        var teaser = RecentlyPlayedTeaserState(capacity: 5)
        teaser.sync(withVisibleIDsNewestFirst: ["a", "b"])
        teaser.remove("b")

        teaser.restore("b", at: 99)

        #expect(teaser.displayedIDs == ["a", "b"])
    }

    @Test func `restore is A no op when the ID is already displayed`() {
        var teaser = RecentlyPlayedTeaserState(capacity: 5)
        teaser.sync(withVisibleIDsNewestFirst: ["a", "b"])

        teaser.restore("a", at: 0)

        #expect(teaser.displayedIDs == ["a", "b"])
    }

    @Test func `restore re trims to capacity if A new play filled the slot meanwhile`() {
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
