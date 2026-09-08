import Foundation
import Testing

@testable import Playback

/// The backoff behind a failed now-playing artwork fetch. Pinned here because
/// the class that uses it (`MediaSessionNowPlayingCenter`) is behind
/// `canImport(NowPlaying)` and cannot be reached from the host suite at all.
struct NowPlayingArtworkRetryPolicyTests {
    private func shouldAttempt(_ attempts: Int, after seconds: Int) -> Bool {
        NowPlayingArtworkRetryPolicy.shouldAttempt(
            afterAttempts: attempts,
            elapsed: .seconds(seconds)
        )
    }

    @Test func neverAttemptedAlwaysFetches() {
        #expect(shouldAttempt(0, after: 0))
    }

    @Test func aFailureIsADelayNotAVerdict() {
        // The regression this exists to prevent: one failed fetch — a tunnel, a
        // dead cell — used to mark a URL unavailable for the whole session, so a
        // station whose artwork missed once showed nothing for the rest of a drive.
        #expect(shouldAttempt(1, after: 0) == false)
        #expect(shouldAttempt(1, after: 5))
    }

    @Test func backoffWidensWithEachFailure() {
        #expect(shouldAttempt(2, after: 14) == false)
        #expect(shouldAttempt(2, after: 15))
        #expect(shouldAttempt(3, after: 44) == false)
        #expect(shouldAttempt(3, after: 45))
        #expect(shouldAttempt(4, after: 119) == false)
        #expect(shouldAttempt(4, after: 120))
    }

    @Test func backoffStillRetriesAfterASeveralMinuteDeadZone() {
        // The whole point: a drive through a long dead zone comes back to a
        // station that can still recover its artwork.
        #expect(shouldAttempt(4, after: 600))
    }

    @Test func aDeadURLStopsBeingRetried() {
        // A 404 on a delisted station favicon costs five fetches per session,
        // not one per track boundary forever.
        #expect(shouldAttempt(NowPlayingArtworkRetryPolicy.maximumAttempts, after: 100_000) == false)
    }

    @Test func delayScheduleIsCapped() {
        #expect(NowPlayingArtworkRetryPolicy.retryDelay(afterAttempts: 1) == .seconds(5))
        #expect(NowPlayingArtworkRetryPolicy.retryDelay(afterAttempts: 4) == .seconds(120))
        // Out-of-range input clamps rather than trapping on the schedule index.
        #expect(NowPlayingArtworkRetryPolicy.retryDelay(afterAttempts: 99) == .seconds(120))
        #expect(NowPlayingArtworkRetryPolicy.retryDelay(afterAttempts: 0) == .seconds(5))
    }
}
