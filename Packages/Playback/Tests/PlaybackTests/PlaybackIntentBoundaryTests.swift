import Foundation
@testable import Playback
import Testing

@MainActor
struct PlaybackIntentBoundaryTests {
    @Test func `pause after output start before status silences output`() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        await waitForStart(output)
        controller.pause()

        #expect(output.stopCount == 1)
        #expect(controller.state == .paused(station()))
    }

    @Test func `station switch stops previous output before resolving next`() async {
        let stationA = station("a")
        let stationB = station("b")
        let output = FakeAudioOutput()
        let controller = makeController(stations: [stationA, stationB], output: output)

        controller.play(stationA)
        await waitForStart(output)
        output.onStatusChange?(.playing)
        controller.play(stationB)

        #expect(output.stopCount == 1)
        controller.pause()
        #expect(controller.state == .paused(stationB))
    }

    @Test func `permanent stream failure does not reconnect`() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.failed(.stationNotAvailable(errorCode: 404)))

        #expect(controller.state == .failed(.stationNotAvailable(errorCode: 404)))
        #expect(controller.reconnectAttempts == 0)
        #expect(controller.playbackRequested == false)
    }

    @Test func `late playing status cannot override pause intent`() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        controller.pause()
        output.onStatusChange?(.playing)

        #expect(controller.state == .paused(station()))
    }

    @Test func `status from previous generation cannot drive new station`() async {
        let stationA = station("a")
        let stationB = station("b")
        let output = FakeAudioOutput()
        let controller = makeController(stations: [stationA, stationB], output: output)

        controller.play(stationA)
        await waitForStart(output)
        let oldGeneration = output.startedStreamGenerations[0]
        controller.play(stationB)
        await waitForStart(output, count: 2)

        output.emit(.playing, generation: oldGeneration)
        #expect(controller.state == .loading(stationB))
        output.emit(.playing, generation: output.startedStreamGenerations[1])
        #expect(controller.state == .playing(stationB))
    }

    @Test func `media services reset waits for listener before restarting`() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.onStatusChange?(.mediaServicesReset)

        #expect(controller.state == .failed(.audioServicesReset))
        #expect(output.startedURLs.count == 1)
        controller.resume()
        await waitForStart(output, count: 2)
        #expect(output.startedURLs.count == 2)
    }

    @Test func `media services reset clears pending route resume`() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.onStatusChange?(.routeLost)
        output.onStatusChange?(.mediaServicesReset)
        output.onStatusChange?(.routeAvailable)

        #expect(controller.state == .failed(.audioServicesReset))
        #expect(output.resumeCount == 0)
        #expect(output.startedURLs.count == 1)
    }

    @Test func `media services reset clears pending interruption resume`() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.onStatusChange?(.interruptionBegan)
        output.onStatusChange?(.mediaServicesReset)
        output.onStatusChange?(.interruptionEnded(shouldResume: true, otherAudioIsPlaying: false))

        #expect(controller.state == .failed(.audioServicesReset))
        #expect(output.resumeCount == 0)
        #expect(output.startedURLs.count == 1)
    }
}
