import Foundation
import Testing

@testable import Playback

@MainActor
struct SleepTimerTests {
    /// Polls until the timer fires or the deadline passes.
    private func waitUntilFired(_ fired: () -> Bool, upTo seconds: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(seconds)
        while fired() == false, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func firesOnceAfterDurationAndDeactivates() async {
        let timer = SleepTimer()
        var fireCount = 0
        timer.onFire = { fireCount += 1 }

        timer.start(duration: 0.05)
        #expect(timer.isActive)
        #expect(timer.fireDate != nil)

        await waitUntilFired { fireCount > 0 }
        #expect(fireCount == 1)
        #expect(timer.isActive == false)
        #expect(timer.fireDate == nil)
    }

    @Test func cancelPreventsFiring() async {
        let timer = SleepTimer()
        var fired = false
        timer.onFire = { fired = true }

        timer.start(duration: 0.05)
        timer.cancel()
        #expect(timer.isActive == false)

        try? await Task.sleep(for: .milliseconds(150))
        #expect(fired == false)
    }

    @Test func restartReplacesThePreviousSchedule() async {
        let timer = SleepTimer()
        var fireCount = 0
        timer.onFire = { fireCount += 1 }

        // A long timer replaced by a short one must fire exactly once (the
        // short one); the cancelled schedule must not fire later.
        timer.start(duration: 60)
        timer.start(duration: 0.05)

        await waitUntilFired { fireCount > 0 }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(fireCount == 1)
        #expect(timer.fireDate == nil)
    }

    @Test func remainingIsDerivedFromInjectedClock() {
        let epoch = Date(timeIntervalSinceReferenceDate: 1_000)
        let timer = SleepTimer(now: { epoch })

        timer.start(duration: 60)

        #expect(timer.remaining(asOf: epoch) == 60)
        #expect(timer.remaining(asOf: epoch.addingTimeInterval(10)) == 50)
        // Never negative, even past the fire date.
        #expect(timer.remaining(asOf: epoch.addingTimeInterval(120)) == 0)

        timer.cancel()
        #expect(timer.remaining(asOf: epoch) == nil)
    }
}
