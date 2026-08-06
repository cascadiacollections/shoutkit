import Foundation
import RadioDirectory
import Testing

@testable import Playback

// What happens to a listener's station when the OS takes the audio session away
// and hands it back: a call, an alarm, Siri, another app claiming playback.
//
// The interesting cases are the ones where iOS does *not* set its `shouldResume`
// hint. Honoring only the hint leaves radio silently paused after interruptions
// that plainly should resume; ignoring the hint entirely starts audio over
// whatever the listener switched to. `PlaybackController` resumes a hintless end
// only when the stream was running when the interruption began, nothing else
// holds audio now, and the interruption ended inside `hintlessResumeWindow`.
// Short injected windows here; the production default is 90 s.

@MainActor
struct PlaybackInterruptionTests {
    private static let shortWindow: Duration = .milliseconds(50)

    /// Plays a station and reports `.playing`, i.e. the state every interruption
    /// case below starts from.
    private func playing(
        output: FakeAudioOutput,
        hintlessResumeWindow: Duration = .seconds(90)
    ) async -> PlaybackController {
        let controller = makeController(
            stations: [station()],
            output: output,
            hintlessResumeWindow: hintlessResumeWindow
        )
        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        #expect(controller.state == .playing(station()))
        return controller
    }

    // MARK: - Ending without the system's resume hint

    @Test func hintlessInterruptionResumesWhenNothingElseHoldsAudio() async {
        let output = FakeAudioOutput()
        let controller = await playing(output: output)

        output.onStatusChange?(.interruptionBegan)
        #expect(controller.state == .paused(station()))

        // The reported case: iOS ends the interruption without `.shouldResume`,
        // and honoring only the hint left the station silent until the listener
        // noticed and pressed play.
        output.onStatusChange?(.interruptionEnded(shouldResume: false, otherAudioIsPlaying: false))
        #expect(controller.state == .playing(station()))
    }

    @Test func hintlessInterruptionStaysPausedWhileAnotherAppHoldsAudio() async {
        let output = FakeAudioOutput()
        let controller = await playing(output: output)

        output.onStatusChange?(.interruptionBegan)
        // The listener started something else during the interruption. Resuming
        // would yank the session back from it.
        output.onStatusChange?(.interruptionEnded(shouldResume: false, otherAudioIsPlaying: true))

        #expect(controller.state == .paused(station()))
        #expect(output.resumeCount == 0)
    }

    @Test func hintlessResumeExpiresWithItsWindow() async {
        let output = FakeAudioOutput()
        let controller = await playing(output: output, hintlessResumeWindow: Self.shortWindow)

        output.onStatusChange?(.interruptionBegan)
        // A long interruption is a listener who moved on, not an alert.
        await waitUntil { controller.mayResumeWithoutSystemHint == false }
        output.onStatusChange?(.interruptionEnded(shouldResume: false, otherAudioIsPlaying: false))

        #expect(controller.state == .paused(station()))
        #expect(output.resumeCount == 0)
    }

    @Test func systemHintResumesEvenAfterTheHintlessWindowCloses() async {
        let output = FakeAudioOutput()
        let controller = await playing(output: output, hintlessResumeWindow: Self.shortWindow)

        output.onStatusChange?(.interruptionBegan)
        await waitUntil { controller.mayResumeWithoutSystemHint == false }
        // The window bounds hintless resumes only; the system's own hint always
        // wins, however long the call ran.
        output.onStatusChange?(.interruptionEnded(shouldResume: true, otherAudioIsPlaying: false))

        #expect(controller.state == .playing(station()))
    }

    // MARK: - Arming

    @Test func interruptionBeginningWhilePausedCannotAutoResume() async {
        let output = FakeAudioOutput()
        let controller = await playing(output: output)

        // A first interruption that the system never ends — iOS doesn't guarantee
        // an `.ended` for every `.began` (a disconnected route, or the app
        // suspended through the interruption).
        output.onStatusChange?(.interruptionBegan)
        #expect(controller.state == .paused(station()))

        // A second interruption begins from that paused state, and *this* one
        // ends with a resume hint. Arming is per-interruption, so the stale arm
        // from the first must not turn this into unrequested audio.
        output.onStatusChange?(.interruptionBegan)
        output.onStatusChange?(.interruptionEnded(shouldResume: true, otherAudioIsPlaying: false))

        #expect(controller.state == .paused(station()))
        #expect(output.resumeCount == 0)
    }

    @Test func interruptionEndedWithoutABeginningDoesNotStartPlayback() async {
        let output = FakeAudioOutput()
        let controller = await playing(output: output)

        controller.pause()
        #expect(controller.state == .paused(station()))

        output.onStatusChange?(.interruptionEnded(shouldResume: true, otherAudioIsPlaying: false))

        #expect(controller.state == .paused(station()))
        #expect(output.resumeCount == 0)
    }

    @Test func pausingDuringAnInterruptionSuppressesAutoResume() async {
        let output = FakeAudioOutput()
        let controller = await playing(output: output)

        output.onStatusChange?(.interruptionBegan)
        // Pausing during the call means "stay paused" when it ends — for the
        // hintless path as much as the hinted one.
        controller.pause()
        output.onStatusChange?(.interruptionEnded(shouldResume: false, otherAudioIsPlaying: false))

        #expect(controller.state == .paused(station()))
        #expect(output.resumeCount == 0)
    }

    @Test func choosingAStationDuringAnInterruptionSuppressesAutoResume() async {
        let output = FakeAudioOutput()
        let controller = await playing(output: output)

        output.onStatusChange?(.interruptionBegan)
        // A fresh listening choice mid-interruption owns the outcome; the
        // interruption ending must not re-drive playback behind it.
        controller.play(station("other"))
        await waitForStart(output, count: 2)
        output.onStatusChange?(.interruptionEnded(shouldResume: true, otherAudioIsPlaying: false))

        #expect(controller.currentStation?.id == "other")
        #expect(output.resumeCount == 0, "the new station is starting; there is nothing to resume")
    }

    @Test func routeReturningResumesOnlyPlaybackPausedByRouteLoss() async {
        let output = FakeAudioOutput()
        let controller = await playing(output: output)

        output.onStatusChange?(.routeLost)
        #expect(controller.state == .paused(station()))
        output.onStatusChange?(.routeAvailable)

        #expect(controller.state == .playing(station()))
        #expect(output.resumeCount == 1)
    }

    @Test func routeReturningDoesNotResumeAfterExplicitPauseOrStop() async {
        let output = FakeAudioOutput()
        let controller = await playing(output: output)

        output.onStatusChange?(.routeLost)
        controller.pause()
        output.onStatusChange?(.routeAvailable)
        #expect(output.resumeCount == 0)

        controller.stop()
        output.onStatusChange?(.routeAvailable)
        #expect(output.resumeCount == 0)
    }

    @Test func startingPlaybackReleasesRouteResumeClaim() async {
        let output = FakeAudioOutput()
        let controller = await playing(output: output)

        output.onStatusChange?(.routeLost)
        controller.resume()
        output.onStatusChange?(.routeAvailable)

        #expect(output.resumeCount == 1)
    }
}
