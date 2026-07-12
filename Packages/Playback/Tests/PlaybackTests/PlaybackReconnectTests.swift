import Foundation
import RadioDirectory
import Testing

@testable import Playback

// Bounded auto-reconnect: a mid-play failure or a stalled stream should retry a
// few times on a backed-off schedule before surfacing a terminal state, and a
// user pause must always win over a pending retry. Short delays and small
// budgets are injected here; production defaults are seconds and 3 attempts.

@MainActor
struct PlaybackReconnectTests {
    private static let fastDelay: Duration = .milliseconds(10)

    @Test func failureReconnectsThenRecovers() async {
        let output = FakeAudioOutput()
        let controller = makeController(
            stations: [station()], output: output,
            maxReconnectAttempts: 3, reconnectBaseDelay: Self.fastDelay
        )

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)

        // A mid-play failure retries rather than surfacing `.failed` at once.
        output.onStatusChange?(.failed(.streamFailed("drop")))
        await waitUntil { output.startedURLs.count == 2 }
        #expect(output.startedURLs.count == 2)

        // The reconnect succeeds.
        output.onStatusChange?(.playing)
        #expect(controller.state == .playing(station()))
    }

    @Test func failureReconnectsUpToBudgetThenSurfacesFailure() async {
        let output = FakeAudioOutput()
        let controller = makeController(
            stations: [station()], output: output,
            maxReconnectAttempts: 2, reconnectBaseDelay: Self.fastDelay
        )

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)

        output.onStatusChange?(.failed(.streamFailed("boom"))) // attempt 1
        await waitUntil { output.startedURLs.count == 2 }
        output.onStatusChange?(.failed(.streamFailed("boom"))) // attempt 2
        await waitUntil { output.startedURLs.count == 3 }
        output.onStatusChange?(.failed(.streamFailed("boom"))) // budget spent → give up

        await waitUntil { controller.state == .failed(.streamFailed("boom")) }
        #expect(output.startedURLs.count == 3, "two reconnects (start #2, #3), then no more")
        #expect(controller.state == .failed(.streamFailed("boom")))
    }

    @Test func recoveryResetsReconnectBudget() async {
        let output = FakeAudioOutput()
        // Budget of 1: without a reset, the second drop could never retry.
        let controller = makeController(
            stations: [station()], output: output,
            maxReconnectAttempts: 1, reconnectBaseDelay: Self.fastDelay
        )

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)

        output.onStatusChange?(.failed(.streamFailed("drop")))
        await waitUntil { output.startedURLs.count == 2 }
        output.onStatusChange?(.playing) // recovered → budget refreshes
        output.onStatusChange?(.failed(.streamFailed("drop")))
        await waitUntil { output.startedURLs.count == 3 }

        #expect(output.startedURLs.count == 3, "a recovery between drops must refresh the budget")
    }

    @Test func pauseCancelsPendingReconnect() async {
        let output = FakeAudioOutput()
        // A long backoff so the test can pause before the retry fires.
        let controller = makeController(
            stations: [station()], output: output,
            maxReconnectAttempts: 3, reconnectBaseDelay: .milliseconds(200)
        )

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.onStatusChange?(.failed(.streamFailed("drop"))) // schedules a retry in 200ms
        controller.pause() // must beat it

        try? await Task.sleep(for: .milliseconds(300))
        #expect(output.startedURLs.count == 1, "a paused stream must not auto-reconnect")
        #expect(controller.state == .paused(station()))
    }

    @Test func stallReconnectsBeforeParking() async {
        let output = FakeAudioOutput()
        let controller = makeController(
            stations: [station()], output: output,
            stallTimeout: .milliseconds(30),
            maxReconnectAttempts: 3, reconnectBaseDelay: Self.fastDelay
        )

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.buffering) // arms the stall ceiling

        // Ceiling fires: the stalled player is torn down and the stream retried.
        await waitUntil { output.startedURLs.count == 2 }
        #expect(output.stopCount == 1)

        output.onStatusChange?(.playing)
        #expect(controller.state == .playing(station()))
    }
}
