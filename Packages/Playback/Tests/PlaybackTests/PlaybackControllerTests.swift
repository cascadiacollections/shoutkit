import Foundation
@testable import Playback
import RadioDirectory
import Testing

// Doubles and builders (FakeAudioOutput, NowPlayingPresenterSpy, station(_:),
// makeController, waitForStart, drainMainQueue) live in PlaybackTestSupport.swift
// and are shared with PlaybackControllerAlbumArtTests.

@MainActor
struct PlaybackControllerTests {
    @Test func `play resolves endpoint and starts output`() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        #expect(controller.state == .loading(station()))

        await waitForStart(output)
        #expect(output.startedURL != nil)
        #expect(controller.currentStation?.id == "kexp")
    }

    @Test func `tap to audio trace ends on first playing status`() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.tapToAudioPrewarmEnabledProvider = { true }
        controller.play(station())
        #expect(controller.tapToAudioTrace != nil)

        await waitForStart(output)
        #expect(controller.tapToAudioTrace != nil)

        output.onStatusChange?(.playing)
        #expect(controller.tapToAudioTrace == nil)
    }

    @Test func `status updates drive playback state`() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        await waitForStart(output)

        output.onStatusChange?(.playing)
        #expect(controller.state == .playing(station()))
        #expect(controller.phase(for: station()) == .playing)

        controller.pause()
        #expect(controller.state == .paused(station()))
        #expect(controller.phase(for: station()) == .paused)
    }

    @Test func `pause during loading cancels pending start`() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        // Pause before the endpoint resolution task has a chance to run.
        controller.pause()

        await drainMainQueue()
        #expect(output.startedURLs.isEmpty, "stream must not start after the user paused")
        #expect(controller.state == .paused(station()))
    }

    @Test func `resume after loading pause replays station`() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        controller.pause()
        await drainMainQueue()
        #expect(output.startedURLs.isEmpty)

        controller.resume()
        await waitForStart(output)
        #expect(output.startedURLs.count == 1)
        #expect(controller.currentStation?.id == "kexp")
    }

    @Test func `rapid station switch only starts the latest`() async {
        let stationA = station("a")
        let stationB = station("b")
        let output = FakeAudioOutput()
        let controller = makeController(stations: [stationA, stationB], output: output)

        controller.play(stationA)
        controller.play(stationB)

        await waitForStart(output)
        await drainMainQueue()

        #expect(output.startedURLs.count == 1, "cancelled resolution must not start a stream")
        #expect(output.startedURL?.absoluteString.contains("b.aac") == true)
        #expect(controller.currentStation?.id == "b")
    }

    @Test func `interruption pauses and resumes when hinted`() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        #expect(controller.state == .playing(station()))

        output.onStatusChange?(.interruptionBegan)
        #expect(controller.state == .paused(station()))

        // FakeAudioOutput.resume() reports .playing, so a resume hint restores playback.
        output.onStatusChange?(.interruptionEnded(shouldResume: true, otherAudioIsPlaying: false))
        #expect(controller.state == .playing(station()))
    }

    @Test func `interruption without resume hint stays paused`() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)

        // No hint *and* another app holding audio: staying paused is the only
        // safe answer (the hintless-resume policy lives in PlaybackInterruptionTests).
        output.onStatusChange?(.interruptionBegan)
        output.onStatusChange?(.interruptionEnded(shouldResume: false, otherAudioIsPlaying: true))
        #expect(controller.state == .paused(station()))
    }

    @Test func `track info becomes now playing metadata`() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.emitTrackInfo("Song", "Band")

        #expect(controller.nowPlaying?.title == "Song")
        #expect(controller.nowPlaying?.artist == "Band")
    }

    @Test func `stale track info from previous stream generation is dropped`() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)

        output.onTrackInfo?(AudioTrackInfo(title: "Old Song", artist: "Old Band", streamGeneration: 0))
        #expect(controller.nowPlaying == nil)

        output.emitTrackInfo("New Song", "New Band")
        #expect(controller.nowPlaying?.title == "New Song")
        #expect(controller.nowPlaying?.artist == "New Band")
    }

    @Test func `stop resets to idle`() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)

        controller.stop()
        #expect(controller.state == .idle)
        #expect(controller.currentStation == nil)
        #expect(output.stopCalled)
    }

    @Test func `on station played fires for every play`() {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station("a"), station("b")], output: output)

        var played: [String] = []
        controller.onStationPlayed = { played.append($0.id) }

        controller.play(station("a"))
        controller.play(station("b"))
        #expect(played == ["a", "b"])
    }

    // MARK: - Lock-screen (NowPlayingPresenting) contract

    @Test func `playing status pushes now playing update`() async {
        let output = FakeAudioOutput()
        let presenter = NowPlayingPresenterSpy()
        let controller = makeController(stations: [station()], output: output, presenter: presenter)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)

        #expect(presenter.lastUpdate == .update(
            stationID: "kexp", trackTitle: nil, isPlaying: true, artwork: .resolved(nil),
        ))
    }

    @Test func `pause during loading tells lock screen not playing`() async {
        let output = FakeAudioOutput()
        let presenter = NowPlayingPresenterSpy()
        let controller = makeController(stations: [station()], output: output, presenter: presenter)

        controller.play(station())
        controller.pause()
        await drainMainQueue()

        // The lock screen must reflect the pause even though no player ever started.
        #expect(presenter.lastUpdate == .update(
            stationID: "kexp", trackTitle: nil, isPlaying: false, artwork: .resolved(nil),
        ))
    }

    @Test func `track info reaches lock screen with title`() async {
        let output = FakeAudioOutput()
        let presenter = NowPlayingPresenterSpy()
        let controller = makeController(stations: [station()], output: output, presenter: presenter)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.emitTrackInfo("Song", "Band")

        #expect(presenter.lastUpdate == .update(
            stationID: "kexp", trackTitle: "Song", isPlaying: true, artwork: .resolved(nil),
        ))
    }

    @Test func `interruption tells lock screen not playing`() async {
        let output = FakeAudioOutput()
        let presenter = NowPlayingPresenterSpy()
        let controller = makeController(stations: [station()], output: output, presenter: presenter)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.onStatusChange?(.interruptionBegan)

        #expect(presenter.lastUpdate == .update(
            stationID: "kexp", trackTitle: nil, isPlaying: false, artwork: .resolved(nil),
        ))
        #expect(controller.state == .paused(station()))
    }

    @Test func `stop clears lock screen`() async {
        let output = FakeAudioOutput()
        let presenter = NowPlayingPresenterSpy()
        let controller = makeController(stations: [station()], output: output, presenter: presenter)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        controller.stop()

        #expect(presenter.events.last == .clear)
    }

    @Test func `remote commands drive the controller`() async {
        let output = FakeAudioOutput()
        let presenter = NowPlayingPresenterSpy()
        let controller = makeController(stations: [station()], output: output, presenter: presenter)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)

        // Lock-screen pause button.
        presenter.onPause?()
        #expect(controller.state == .paused(station()))

        // Lock-screen play button.
        presenter.onPlay?()
        #expect(controller.state == .playing(station()))

        // Lock-screen toggle (e.g. headphone remote).
        presenter.onToggle?()
        #expect(controller.state == .paused(station()))

        // Lock-screen stop.
        presenter.onStop?()
        #expect(controller.state == .idle)
    }

    // MARK: - ICY metadata parsing

    @Test func `icy metadata parses artist and title`() {
        let info = ICYMetadataParser.parseTrack(from: "Radiohead - Weird Fishes")
        #expect(info.artist == "Radiohead")
        #expect(info.title == "Weird Fishes")
    }

    @Test func `icy metadata without separator is title only`() {
        let info = ICYMetadataParser.parseTrack(from: "Station Jingle")
        #expect(info.artist == nil)
        #expect(info.title == "Station Jingle")
    }

    @Test func `icy metadata splits on first separator only`() {
        let info = ICYMetadataParser.parseTrack(from: "Artist - Title - Live Session")
        #expect(info.artist == "Artist")
        #expect(info.title == "Title - Live Session")
    }

    @Test func `icy metadata with empty artist is nil`() {
        let info = ICYMetadataParser.parseTrack(from: " - Orphan Title")
        #expect(info.artist == nil)
        #expect(info.title == "Orphan Title")
    }
}
