import Foundation
import RadioDirectory
import Testing

@testable import Playback

// The paths that used to leave playback stuck after a pause: tapping play did
// nothing at all — no audio, no error — until the listener switched stations and
// back. `output.resume()` is best-effort, and a streaming engine can refuse to
// resume a player whose stream is already gone without saying so, which is what
// happens once the engine's own state has drifted from the controller's (the
// system stops the audio engine for an interruption without telling it; a live
// stream the server closes ends the same way). Two guards, tested here: the
// controller keeps the output's state in step, and a resume nothing acknowledges
// rejoins the stream. Short injected watchdog windows; the default is 2 s.

@MainActor
struct PlaybackResumeRecoveryTests {
    private static let shortTimeout: Duration = .milliseconds(50)

    // MARK: - Resume watchdog

    @Test func resumeTheOutputNeverAcknowledgesRejoinsStream() async {
        let output = FakeAudioOutput()
        let controller = makeController(
            stations: [station()], output: output,
            resumeWatchdogTimeout: Self.shortTimeout
        )

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        controller.pause()
        #expect(controller.state == .paused(station()))

        // The engine's player is past resuming, and says nothing about it.
        output.resumeSilentlyFails = true
        controller.togglePlayPause()
        #expect(output.resumeCount == 1)

        await waitUntil { output.startedURLs.count == 2 }
        #expect(output.startedURLs.count == 2, "an unacknowledged resume must rejoin the stream")
        #expect(output.stopCount == 1, "the dead player is torn down before the rejoin")

        output.onStatusChange?(.playing)
        #expect(controller.state == .playing(station()))
    }

    @Test func acknowledgedResumeDoesNotRejoinStream() async {
        let output = FakeAudioOutput()
        let controller = makeController(
            stations: [station()], output: output,
            resumeWatchdogTimeout: Self.shortTimeout
        )

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        controller.pause()
        controller.togglePlayPause()

        try? await Task.sleep(for: .milliseconds(150))
        #expect(output.startedURLs.count == 1, "a resume that took effect must not restart the stream")
        #expect(output.stopCount == 0)
        #expect(controller.state == .playing(station()))
    }

    @Test func pauseCancelsResumeWatchdog() async {
        let output = FakeAudioOutput()
        let controller = makeController(
            stations: [station()], output: output,
            resumeWatchdogTimeout: Self.shortTimeout
        )

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        controller.pause()

        output.resumeSilentlyFails = true
        controller.resume() // arms the watchdog
        controller.pause() // must beat it

        try? await Task.sleep(for: .milliseconds(150))
        #expect(output.startedURLs.count == 1, "a paused stream must not be rejoined")
        #expect(controller.state == .paused(station()))
    }

    @Test func stopCancelsResumeWatchdog() async {
        let output = FakeAudioOutput()
        let controller = makeController(
            stations: [station()], output: output,
            resumeWatchdogTimeout: Self.shortTimeout
        )

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        controller.pause()

        output.resumeSilentlyFails = true
        controller.resume()
        controller.stop()

        try? await Task.sleep(for: .milliseconds(150))
        #expect(output.startedURLs.count == 1)
        #expect(controller.state == .idle)
    }

    @Test func rejoinReusesResolvedEndpointAndIsNotANewChoice() async {
        let output = FakeAudioOutput()
        let directory = CountingRadioDirectory(stations: [station()])
        let controller = makeController(
            directory: directory, output: output,
            resumeWatchdogTimeout: Self.shortTimeout
        )
        var playedCount = 0
        controller.onStationPlayed = { _ in playedCount += 1 }

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.emitTrackInfo("Song", "Band")
        controller.pause()

        output.resumeSilentlyFails = true
        controller.resume()
        await waitUntil { output.startedURLs.count == 2 }

        #expect(output.startedURLs.count == 2)
        #expect(await directory.streamEndpointCallCount == 1, "a rejoin must reuse the cached endpoint")
        #expect(playedCount == 1, "a rejoin is not a new listening choice")
        #expect(controller.nowPlaying?.title == "Song", "the last-known track stays put while re-buffering")
    }

    // MARK: - Keeping the output's state in step

    @Test func interruptionPausesTheOutputToo() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.onStatusChange?(.interruptionBegan)

        // Not just the controller's own state: the system silences the audio
        // without telling the streaming engine, and an engine that never learned
        // it was paused can refuse to resume when the interruption ends.
        #expect(output.pauseCount == 1)
        #expect(controller.state == .paused(station()))
    }

    @Test func interruptionDuringLoadingTearsDownAStartedOutput() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        await waitForStart(output)
        // No status has landed yet, so the controller is still `.loading` even
        // though the stream itself is already running.
        #expect(controller.state == .loading(station()))

        output.onStatusChange?(.interruptionBegan)
        #expect(output.stopCount == 1, "a started stream must not run on through the interruption")
        #expect(output.pauseCount == 0, "there is no player left to pause")
        #expect(controller.state == .paused(station()))

        // Auto-resume restarts instead of resuming a torn-down player.
        output.onStatusChange?(.interruptionEnded(shouldResume: true))
        await waitForStart(output, count: 2)
        #expect(output.startedURLs.count == 2)
        #expect(output.resumeCount == 0)
    }
}
