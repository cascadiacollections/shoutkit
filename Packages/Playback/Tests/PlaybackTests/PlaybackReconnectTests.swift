import Clocks
import ConcurrencyExtras
import Foundation
@testable import Playback
import RadioDirectory
import Testing

// Bounded auto-reconnect: a mid-play failure or a stalled stream should retry a
// few times on a backed-off schedule before surfacing a terminal state, and a
// user pause must always win over a pending retry. The delays run on a
// `TestClock`, so the suite does not wait them out.

extension MainSerialExecutorTests {
    @MainActor
    struct PlaybackReconnectTests {
        private static let fastDelay: Duration = .milliseconds(10)

        @Test func `failure reconnects then recovers`() async {
            await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let clock = TestClock()
                let controller = makeController(
                    stations: [station()], output: output,
                    maxReconnectAttempts: 3, reconnectBaseDelay: Self.fastDelay, clock: clock,
                )

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.playing)

                // A mid-play failure retries rather than surfacing `.failed` at once.
                let failedGeneration = output.startedStreamGenerations[0]
                output.onStatusChange?(.failed(.streamFailed("drop")))
                output.emit(.playing, generation: failedGeneration)
                #expect(controller.isReconnecting)
                #expect(controller.state == .buffering(station()))
                await clock.advance(by: Self.fastDelay)
                await waitUntil { output.startedURLs.count == 2 }
                #expect(output.startedURLs.count == 2)

                // The reconnect succeeds.
                output.onStatusChange?(.playing)
                #expect(controller.state == .playing(station()))
            }
        }

        @Test func `reconnect reuses resolved endpoint instead of re resolving`() async {
            await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let clock = TestClock()
                let directory = CountingRadioDirectory(stations: [station()])
                let controller = makeController(
                    directory: directory, output: output,
                    maxReconnectAttempts: 3, reconnectBaseDelay: Self.fastDelay, clock: clock,
                )

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.playing)
                #expect(await directory.streamEndpointCallCount == 1)

                // A mid-play failure reconnects — but must reuse the endpoint resolved
                // for the first attempt rather than resolving again.
                output.onStatusChange?(.failed(.streamFailed("drop")))
                await clock.advance(by: Self.fastDelay)
                await waitUntil { output.startedURLs.count == 2 }
                #expect(output.startedURLs.count == 2)
                #expect(await directory.streamEndpointCallCount == 1, "reconnect must reuse the cached endpoint")

                // A fresh play() re-resolves. That path does not wait on the clock.
                controller.play(station())
                await waitUntil { output.startedURLs.count == 3 }
                #expect(await directory.streamEndpointCallCount == 2)
            }
        }

        @Test func `failure reconnects up to budget then surfaces failure`() async {
            await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let clock = TestClock()
                let controller = makeController(
                    stations: [station()], output: output,
                    maxReconnectAttempts: 2, reconnectBaseDelay: Self.fastDelay, clock: clock,
                )

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.playing)

                output.onStatusChange?(.failed(.streamFailed("boom"))) // attempt 1, delay × 1
                await clock.advance(by: Self.fastDelay)
                await waitUntil { output.startedURLs.count == 2 }
                output.onStatusChange?(.failed(.streamFailed("boom"))) // attempt 2, delay × 2
                await clock.advance(by: .milliseconds(20))
                await waitUntil { output.startedURLs.count == 3 }
                output.onStatusChange?(.failed(.streamFailed("boom"))) // budget spent → give up

                #expect(output.startedURLs.count == 3, "two reconnects (start #2, #3), then no more")
                #expect(controller.state == .failed(.streamFailed("boom")))
            }
        }

        @Test func `recovery resets reconnect budget`() async {
            await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let clock = TestClock()
                // Budget of 1: without a reset, the second drop could never retry.
                let controller = makeController(
                    stations: [station()], output: output,
                    maxReconnectAttempts: 1, reconnectBaseDelay: Self.fastDelay, clock: clock,
                )

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.playing)

                output.onStatusChange?(.failed(.streamFailed("drop")))
                #expect(controller.isReconnecting)
                await clock.advance(by: Self.fastDelay)
                await waitUntil { output.startedURLs.count == 2 }
                output.onStatusChange?(.playing) // recovered → budget refreshes
                #expect(controller.isReconnecting == false)
                output.onStatusChange?(.failed(.streamFailed("drop")))
                await clock.advance(by: Self.fastDelay)
                await waitUntil { output.startedURLs.count == 3 }

                #expect(output.startedURLs.count == 3, "a recovery between drops must refresh the budget")
            }
        }

        @Test func `pause cancels pending reconnect`() async {
            await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let clock = TestClock()
                let controller = makeController(
                    stations: [station()], output: output,
                    maxReconnectAttempts: 3, reconnectBaseDelay: .seconds(2), clock: clock,
                )

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.playing)
                output.onStatusChange?(.failed(.streamFailed("drop")))
                await expectSleeping(on: clock)
                controller.pause()

                await clock.advance(by: .seconds(2))
                #expect(output.startedURLs.count == 1, "a paused stream must not auto-reconnect")
                #expect(controller.state == .paused(station()))
            }
        }

        @Test func `reconnect backoff is the base delay, then double`() async {
            await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let clock = TestClock()
                let base: Duration = .seconds(2)
                let controller = makeController(
                    stations: [station()], output: output,
                    maxReconnectAttempts: 3, reconnectBaseDelay: base, clock: clock,
                )

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.playing)
                output.onStatusChange?(.failed(.streamFailed("drop")))

                await clock.advance(by: .seconds(1))
                await expectSleeping(on: clock)
                #expect(output.startedURLs.count == 1, "half the first backoff must not reconnect yet")
                await clock.advance(by: .seconds(1))
                await waitUntil { output.startedURLs.count == 2 }

                output.onStatusChange?(.failed(.streamFailed("drop")))
                await clock.advance(by: .seconds(3))
                await expectSleeping(on: clock)
                #expect(output.startedURLs.count == 2, "the second backoff is four seconds")
                await clock.advance(by: .seconds(1))
                await waitUntil { output.startedURLs.count == 3 }
            }
        }

        @Test func `stall ceiling waits out the connecting timeout`() async {
            await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let clock = TestClock()
                let timeout: Duration = .seconds(30)
                let controller = makeController(
                    stations: [station()], output: output,
                    stallTimeout: timeout, maxReconnectAttempts: 0, clock: clock,
                )

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.buffering)

                await clock.advance(by: .seconds(29))
                await expectSleeping(on: clock)
                #expect(output.stopCount == 0)
                #expect(controller.state == .buffering(station()))

                await clock.advance(by: .seconds(1))
                await waitUntil { output.stopCount == 1 }
                #expect(output.stopCount == 1)
                #expect(controller.state == .failed(.streamStalled))
            }
        }

        @Test func `stall reconnects before parking`() async {
            await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let clock = TestClock()
                let controller = makeController(
                    stations: [station()], output: output,
                    stallTimeout: .milliseconds(30),
                    maxReconnectAttempts: 3, reconnectBaseDelay: Self.fastDelay, clock: clock,
                )

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.buffering)

                let stalledGeneration = output.startedStreamGenerations[0]
                await clock.advance(by: .milliseconds(30))
                await waitUntil { output.stopCount == 1 }
                #expect(output.stopCount == 1)
                let recoveryState = controller.state
                output.emit(.playing, generation: stalledGeneration)
                #expect(controller.isReconnecting)
                #expect(controller.state == recoveryState)
                await clock.advance(by: Self.fastDelay)
                await waitUntil { output.startedURLs.count == 2 }
                #expect(output.stopCount == 1)
                #expect(controller.state == .loading(station()))
                output.emit(.playing, generation: stalledGeneration)
                #expect(controller.state == .loading(station()))

                output.onStatusChange?(.playing)
                #expect(controller.state == .playing(station()))
            }
        }
    }
}
