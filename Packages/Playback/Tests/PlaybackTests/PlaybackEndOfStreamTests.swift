import Foundation
import RadioDirectory
import Testing

@testable import Playback

// A station that broadcasts a fixed-length programme (NPR's hourly newscast is
// the reported case) reaches the end of its content. That is not a dropped
// stream, and the difference is the whole point of `.endOfStream`: routed
// through `.failed`, the bounded auto-reconnect rejoined the finished broadcast
// from the top and played it again for every attempt in the budget.
//
// Default: play once, then park as `.paused` with a play button that replays it.
// Opted in: start over, as an internal restart rather than a new listening choice.

@MainActor
struct PlaybackEndOfStreamTests {
    private static let fastDelay: Duration = .milliseconds(10)

    @Test func endOfStreamStopsInsteadOfLoopingByDefault() async {
        let output = FakeAudioOutput()
        let controller = makeController(
            stations: [station()], output: output,
            maxReconnectAttempts: 3, reconnectBaseDelay: Self.fastDelay
        )

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)

        output.onStatusChange?(.endOfStream)

        #expect(controller.state == .paused(station()))
        #expect(output.stopCalled, "the spent player must not stay resident")

        // The one regression this suite exists for: no restart, now or after the
        // reconnect backoff would have fired.
        try? await Task.sleep(for: .milliseconds(60))
        #expect(output.startedURLs.count == 1, "a finished broadcast must not replay itself")
        #expect(controller.state == .paused(station()))
    }

    @Test func endOfStreamKeepsTheStationRecoverable() async {
        let output = FakeAudioOutput()
        let presenter = NowPlayingPresenterSpy()
        let controller = makeController(stations: [station()], output: output, presenter: presenter)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.onStatusChange?(.endOfStream)

        // The lock screen shows the station, paused — not a cleared surface and
        // not a stream still claiming to play.
        #expect(presenter.lastUpdate == .update(
            stationID: station().id,
            trackTitle: nil,
            isPlaying: false,
            artwork: .resolved(nil)
        ))
        #expect(controller.currentStation == station())

        // Play replays the programme: the player was torn down, so this takes
        // the restart path rather than resuming a stream parked at its end.
        controller.resume()
        await waitUntil { output.startedURLs.count == 2 }
        #expect(output.startedURLs.count == 2)
    }

    @Test func endOfStreamRestartsTheStreamWhenLoopingIsEnabled() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)
        controller.isStreamLoopingEnabledProvider = { true }

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)

        output.onStatusChange?(.endOfStream)
        await waitUntil { output.startedURLs.count == 2 }
        #expect(output.startedURLs.count == 2)
        #expect(output.startedURLs[0] == output.startedURLs[1])

        output.onStatusChange?(.playing)
        #expect(controller.state == .playing(station()))
    }

    @Test func loopingIsReadAtEachEndingRatherThanAtPlay() async {
        let output = FakeAudioOutput()
        var isLoopingEnabled = false
        let controller = makeController(stations: [station()], output: output)
        controller.isStreamLoopingEnabledProvider = { isLoopingEnabled }

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)

        // Flipping the setting mid-programme applies to the programme playing,
        // not only to the next station the listener picks.
        isLoopingEnabled = true
        output.onStatusChange?(.endOfStream)
        await waitUntil { output.startedURLs.count == 2 }
        #expect(output.startedURLs.count == 2)
    }

    @Test func loopRestartIsNotANewListeningChoice() async {
        let output = FakeAudioOutput()
        let directory = CountingRadioDirectory(stations: [station()])
        let controller = makeController(directory: directory, output: output)
        controller.isStreamLoopingEnabledProvider = { true }

        var playedCount = 0
        controller.onStationPlayed = { _ in playedCount += 1 }

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)

        output.onStatusChange?(.endOfStream)
        await waitUntil { output.startedURLs.count == 2 }

        // Recents and Radio-Browser play reporting hang off `onStationPlayed`;
        // a loop would otherwise log one listening session as many.
        #expect(playedCount == 1)
        #expect(await directory.streamEndpointCallCount == 1, "a loop restart reuses the resolved endpoint")
    }

    @Test func endOfStreamRefillsTheReconnectBudget() async {
        let output = FakeAudioOutput()
        let controller = makeController(
            stations: [station()], output: output,
            maxReconnectAttempts: 2, reconnectBaseDelay: Self.fastDelay
        )

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)

        // Spend one attempt on a genuine drop — and deliberately don't report
        // `.playing` for the retry, so nothing else refills the budget.
        output.onStatusChange?(.failed(.streamFailed("drop")))
        await waitUntil { output.startedURLs.count == 2 }
        output.onStatusChange?(.endOfStream)

        // Replay it, then drop twice: a clean ending is a success, so both
        // attempts are available rather than only the one the drop left behind.
        controller.resume()
        await waitUntil { output.startedURLs.count == 3 }
        output.onStatusChange?(.failed(.streamFailed("drop")))
        await waitUntil { output.startedURLs.count == 4 }
        output.onStatusChange?(.failed(.streamFailed("drop")))
        await waitUntil { output.startedURLs.count == 5 }
        #expect(output.startedURLs.count == 5)
    }

    @Test func pauseWinsOverALoopRestartAlreadyUnderway() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)
        controller.isStreamLoopingEnabledProvider = { true }

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)

        output.onStatusChange?(.endOfStream)
        await waitUntil { output.startedURLs.count == 2 }
        output.onStatusChange?(.playing)

        // A listener who pauses the second play-through stays paused: the loop
        // restarts an ending, and a pause is not one.
        controller.pause()
        #expect(controller.state == .paused(station()))
        try? await Task.sleep(for: .milliseconds(60))
        #expect(output.startedURLs.count == 2)
    }
}
