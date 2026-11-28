import Clocks
import ConcurrencyExtras
import Foundation
@testable import Playback
import Testing

extension MainSerialExecutorTests {
    @MainActor
    struct SleepTimerTests {
        @Test func `fires once after duration and deactivates`() async {
            await withMainSerialExecutor {
                let clock = TestClock()
                let timer = SleepTimer(clock: clock)
                var fireCount = 0
                timer.onFire = { fireCount += 1 }

                timer.start(duration: 60)
                #expect(timer.isActive)
                #expect(timer.fireDate != nil)

                await clock.advance(by: .seconds(59))
                await expectSleeping(on: clock)
                #expect(fireCount == 0)
                await clock.advance(by: .seconds(1))
                await waitUntil { fireCount == 1 }
                #expect(fireCount == 1)
                #expect(timer.isActive == false)
                #expect(timer.fireDate == nil)

                await clock.advance(by: .seconds(60))
                #expect(fireCount == 1)
            }
        }

        @Test func `cancel prevents firing`() async {
            await withMainSerialExecutor {
                let clock = TestClock()
                let timer = SleepTimer(clock: clock)
                var fired = false
                timer.onFire = { fired = true }

                timer.start(duration: 5)
                await expectSleeping(on: clock)
                timer.cancel()
                #expect(timer.isActive == false)

                await clock.advance(by: .seconds(5))
                #expect(fired == false)
            }
        }

        @Test func `restart replaces the previous schedule`() async {
            await withMainSerialExecutor {
                let clock = TestClock()
                let timer = SleepTimer(clock: clock)
                var fireCount = 0
                timer.onFire = { fireCount += 1 }

                // A long timer replaced by a short one must fire exactly once (the
                // short one); the cancelled schedule must not fire later.
                timer.start(duration: 60)
                timer.start(duration: 5)

                await clock.advance(by: .seconds(5))
                await waitUntil { fireCount == 1 }
                #expect(fireCount == 1)
                await clock.advance(by: .seconds(60))
                #expect(fireCount == 1)
                #expect(timer.fireDate == nil)
            }
        }

        @Test func `remaining is derived from injected clock`() {
            let epoch = Date(timeIntervalSinceReferenceDate: 1000)
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
}
