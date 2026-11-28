import Clocks
import ConcurrencyExtras
import Foundation
@testable import Playback
import RadioDirectory
import Testing

// Battery hygiene: a paused stream must release the player and audio session
// after a timeout, and a stalled (endlessly buffering) stream must be parked
// instead of retrying forever. The windows run on a `TestClock`.

extension PlaybackTimingTests {
    @MainActor
    struct PlaybackResourceHygieneTests {
        private static let shortTimeout: Duration = .milliseconds(50)

        private func timed(
            output: FakeAudioOutput,
            presenter: NowPlayingPresenterSpy = NowPlayingPresenterSpy(),
            pausedReleaseTimeout: Duration = .seconds(10 * 60),
            stallTimeout: Duration = .seconds(30),
            maxReconnectAttempts: Int = 3,
        ) -> (PlaybackController, TestClock<Duration>) {
            let clock = TestClock()
            let controller = makeController(
                stations: [station()], output: output, presenter: presenter,
                pausedReleaseTimeout: pausedReleaseTimeout, stallTimeout: stallTimeout,
                maxReconnectAttempts: maxReconnectAttempts, clock: clock,
            )
            return (controller, clock)
        }

        // MARK: - Paused release

        @Test func `paused stream releases output after timeout`() async {
            await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let presenter = NowPlayingPresenterSpy()
                let (controller, clock) = timed(
                    output: output, presenter: presenter, pausedReleaseTimeout: Self.shortTimeout,
                )

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.playing)
                controller.pause()

                await clock.advance(by: Self.shortTimeout)
                await waitUntil { output.stopCount == 1 }
                #expect(output.stopCount == 1)
                // The release is invisible: still paused, lock screen never cleared,
                // last surface push is the pause itself.
                #expect(controller.state == .paused(station()))
                #expect(presenter.events.contains(.clear) == false)
                #expect(presenter.lastUpdate == .update(
                    stationID: "kexp", trackTitle: nil, isPlaying: false, artwork: .resolved(nil),
                ))
            }
        }

        @Test func `resume before release timeout keeps player`() async {
            await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let (controller, clock) = timed(output: output, pausedReleaseTimeout: Self.shortTimeout)

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.playing)
                controller.pause()
                await expectSleeping(on: clock)
                controller.resume()

                await clock.advance(by: Self.shortTimeout)
                #expect(output.stopCount == 0)
                #expect(output.resumeCount == 1)
                #expect(output.startedURLs.count == 1, "resume must not restart the stream")
                #expect(controller.state == .playing(station()))
            }
        }

        @Test func `lock screen play after release restarts stream`() async {
            await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let presenter = NowPlayingPresenterSpy()
                let (controller, clock) = timed(
                    output: output, presenter: presenter, pausedReleaseTimeout: Self.shortTimeout,
                )

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.playing)
                controller.pause()
                await clock.advance(by: Self.shortTimeout)
                await waitUntil { output.stopCount == 1 }
                #expect(output.stopCount == 1)

                // The lock-screen play button must still work after the teardown.
                presenter.onPlay?()
                await waitForStart(output, count: 2)
                #expect(output.startedURLs.count == 2)
                #expect(output.resumeCount == 0, "a released player cannot be resumed, only restarted")
                #expect(controller.currentStation?.id == "kexp")
            }
        }

        @Test func `release restart does not refire station played`() async {
            await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let (controller, clock) = timed(output: output, pausedReleaseTimeout: Self.shortTimeout)
                var playedCount = 0
                controller.onStationPlayed = { _ in playedCount += 1 }

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.playing)
                controller.pause()
                await clock.advance(by: Self.shortTimeout)
                await waitUntil { output.stopCount == 1 }
                #expect(output.stopCount == 1)

                controller.resume()
                await waitForStart(output, count: 2)
                #expect(output.startedURLs.count == 2)
                #expect(playedCount == 1, "an internal restart is not a new listening choice")
            }
        }

        @Test func `stop cancels paused release timer`() async {
            await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let (controller, clock) = timed(output: output, pausedReleaseTimeout: Self.shortTimeout)

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.playing)
                controller.pause()
                await expectSleeping(on: clock)
                controller.stop()

                await clock.advance(by: Self.shortTimeout)
                #expect(output.stopCount == 1, "only the explicit stop, not a later release")
                #expect(controller.state == .idle)
            }
        }

        @Test func `interruption outlasting release timeout still auto resumes`() async {
            await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let (controller, clock) = timed(output: output, pausedReleaseTimeout: Self.shortTimeout)

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.playing)
                output.onStatusChange?(.interruptionBegan)

                // The interruption (e.g. a long phone call) outlasts the release.
                await clock.advance(by: Self.shortTimeout)
                await waitUntil { output.stopCount == 1 }
                #expect(output.stopCount == 1)

                output.onStatusChange?(.interruptionEnded(shouldResume: true, otherAudioIsPlaying: false))
                await waitForStart(output, count: 2)
                #expect(output.startedURLs.count == 2, "resume hint must restart the released stream")
            }
        }

        // MARK: - Stall ceiling

        @Test func `stalled buffering surfaces retry after ceiling`() async {
            await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let presenter = NowPlayingPresenterSpy()
                let (controller, clock) = timed(
                    output: output, presenter: presenter,
                    stallTimeout: Self.shortTimeout, maxReconnectAttempts: 0,
                )

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.buffering)

                await clock.advance(by: Self.shortTimeout)
                await waitUntil { output.stopCount == 1 }
                #expect(output.stopCount == 1)
                #expect(controller.state == .failed(.streamStalled))
                // Teardown suppresses the player's own status callback, so the
                // controller must have pushed the stopped surface itself.
                #expect(presenter.lastUpdate == .update(
                    stationID: "kexp", trackTitle: nil, isPlaying: false, artwork: .resolved(nil),
                ))
            }
        }

        @Test func `buffering that recovers cancels stall ceiling`() async {
            await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let (controller, clock) = timed(output: output, stallTimeout: Self.shortTimeout)

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.buffering)
                await expectSleeping(on: clock)
                output.onStatusChange?(.playing)

                await clock.advance(by: Self.shortTimeout)
                #expect(output.stopCount == 0)
                #expect(controller.state == .playing(station()))
            }
        }

        @Test func `play after stall park restarts stream`() async {
            await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let presenter = NowPlayingPresenterSpy()
                let (controller, clock) = timed(
                    output: output, presenter: presenter,
                    stallTimeout: Self.shortTimeout, maxReconnectAttempts: 0,
                )

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.buffering)
                await clock.advance(by: Self.shortTimeout)
                await waitUntil { output.stopCount == 1 }
                #expect(output.stopCount == 1)

                presenter.onPlay?()
                await waitForStart(output, count: 2)
                #expect(output.startedURLs.count == 2)
            }
        }
    }
}
