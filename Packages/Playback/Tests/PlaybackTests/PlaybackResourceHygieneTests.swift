import Foundation
import RadioDirectory
import Testing

@testable import Playback

// Battery hygiene: a paused stream must release the player and audio session
// after a timeout, and a stalled (endlessly buffering) stream must be parked
// instead of retrying forever. Both use short injected timeouts here; the
// production defaults are minutes.

@MainActor
struct PlaybackResourceHygieneTests {
    private static let shortTimeout: Duration = .milliseconds(50)

    // MARK: - Paused release

    @Test func pausedStreamReleasesOutputAfterTimeout() async {
        let output = FakeAudioOutput()
        let presenter = NowPlayingPresenterSpy()
        let controller = makeController(
            stations: [station()], output: output, presenter: presenter,
            pausedReleaseTimeout: Self.shortTimeout
        )

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        controller.pause()

        await waitUntil { output.stopCount == 1 }
        #expect(output.stopCount == 1)
        // The release is invisible: still paused, lock screen never cleared,
        // last surface push is the pause itself.
        #expect(controller.state == .paused(station()))
        #expect(presenter.events.contains(.clear) == false)
        #expect(presenter.lastUpdate == .update(
            stationID: "kexp", trackTitle: nil, isPlaying: false, artworkURL: nil
        ))
    }

    @Test func resumeBeforeReleaseTimeoutKeepsPlayer() async {
        let output = FakeAudioOutput()
        let controller = makeController(
            stations: [station()], output: output,
            pausedReleaseTimeout: Self.shortTimeout
        )

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        controller.pause()
        controller.resume()

        try? await Task.sleep(for: .milliseconds(150))
        #expect(output.stopCount == 0)
        #expect(output.resumeCount == 1)
        #expect(output.startedURLs.count == 1, "resume must not restart the stream")
        #expect(controller.state == .playing(station()))
    }

    @Test func lockScreenPlayAfterReleaseRestartsStream() async {
        let output = FakeAudioOutput()
        let presenter = NowPlayingPresenterSpy()
        let controller = makeController(
            stations: [station()], output: output, presenter: presenter,
            pausedReleaseTimeout: Self.shortTimeout
        )

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        controller.pause()
        await waitUntil { output.stopCount == 1 }

        // The lock-screen play button must still work after the teardown.
        presenter.onPlay?()
        await waitForStart(output, count: 2)
        #expect(output.startedURLs.count == 2)
        #expect(output.resumeCount == 0, "a released player cannot be resumed, only restarted")
        #expect(controller.currentStation?.id == "kexp")
    }

    @Test func releaseRestartDoesNotRefireStationPlayed() async {
        let output = FakeAudioOutput()
        let controller = makeController(
            stations: [station()], output: output,
            pausedReleaseTimeout: Self.shortTimeout
        )
        var playedCount = 0
        controller.onStationPlayed = { _ in playedCount += 1 }

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        controller.pause()
        await waitUntil { output.stopCount == 1 }

        controller.resume()
        await waitForStart(output, count: 2)
        #expect(output.startedURLs.count == 2)
        #expect(playedCount == 1, "an internal restart is not a new listening choice")
    }

    @Test func stopCancelsPausedReleaseTimer() async {
        let output = FakeAudioOutput()
        let controller = makeController(
            stations: [station()], output: output,
            pausedReleaseTimeout: Self.shortTimeout
        )

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        controller.pause()
        controller.stop()

        try? await Task.sleep(for: .milliseconds(150))
        #expect(output.stopCount == 1, "only the explicit stop, not a later release")
        #expect(controller.state == .idle)
    }

    @Test func interruptionOutlastingReleaseTimeoutStillAutoResumes() async {
        let output = FakeAudioOutput()
        let controller = makeController(
            stations: [station()], output: output,
            pausedReleaseTimeout: Self.shortTimeout
        )

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.onStatusChange?(.interruptionBegan)

        // The interruption (e.g. a long phone call) outlasts the release.
        await waitUntil { output.stopCount == 1 }

        output.onStatusChange?(.interruptionEnded(shouldResume: true))
        await waitForStart(output, count: 2)
        #expect(output.startedURLs.count == 2, "resume hint must restart the released stream")
    }

    // MARK: - Stall ceiling

    @Test func stalledBufferingParksAsPausedAfterCeiling() async {
        let output = FakeAudioOutput()
        let presenter = NowPlayingPresenterSpy()
        let controller = makeController(
            stations: [station()], output: output, presenter: presenter,
            stallTimeout: Self.shortTimeout, maxReconnectAttempts: 0
        )

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.buffering)

        await waitUntil { output.stopCount == 1 }
        #expect(output.stopCount == 1)
        #expect(controller.state == .paused(station()))
        // Teardown suppresses the player's own status callback, so the
        // controller must have pushed the paused surface itself.
        #expect(presenter.lastUpdate == .update(
            stationID: "kexp", trackTitle: nil, isPlaying: false, artworkURL: nil
        ))
    }

    @Test func bufferingThatRecoversCancelsStallCeiling() async {
        let output = FakeAudioOutput()
        let controller = makeController(
            stations: [station()], output: output,
            stallTimeout: Self.shortTimeout
        )

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.buffering)
        output.onStatusChange?(.playing)

        try? await Task.sleep(for: .milliseconds(150))
        #expect(output.stopCount == 0)
        #expect(controller.state == .playing(station()))
    }

    @Test func playAfterStallParkRestartsStream() async {
        let output = FakeAudioOutput()
        let presenter = NowPlayingPresenterSpy()
        let controller = makeController(
            stations: [station()], output: output, presenter: presenter,
            stallTimeout: Self.shortTimeout, maxReconnectAttempts: 0
        )

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.buffering)
        await waitUntil { output.stopCount == 1 }

        presenter.onPlay?()
        await waitForStart(output, count: 2)
        #expect(output.startedURLs.count == 2)
    }
}
