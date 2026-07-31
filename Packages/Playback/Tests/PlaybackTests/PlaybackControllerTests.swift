import Foundation
import RadioDirectory
import Testing

@testable import Playback

// Doubles and builders (FakeAudioOutput, NowPlayingPresenterSpy, station(_:),
// makeController, waitForStart, drainMainQueue) live in PlaybackTestSupport.swift
// and are shared with PlaybackControllerAlbumArtTests.

@MainActor
struct PlaybackControllerTests {
    @Test func playResolvesEndpointAndStartsOutput() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        #expect(controller.state == .loading(station()))

        await waitForStart(output)
        #expect(output.startedURL != nil)
        #expect(controller.currentStation?.id == "kexp")
    }

    @Test func tapToAudioTraceEndsOnFirstPlayingStatus() async {
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

    @Test func statusUpdatesDrivePlaybackState() async {
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

    @Test func pauseDuringLoadingCancelsPendingStart() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        // Pause before the endpoint resolution task has a chance to run.
        controller.pause()

        await drainMainQueue()
        #expect(output.startedURLs.isEmpty, "stream must not start after the user paused")
        #expect(controller.state == .paused(station()))
    }

    @Test func resumeAfterLoadingPauseReplaysStation() async {
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

    @Test func rapidStationSwitchOnlyStartsTheLatest() async {
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

    @Test func interruptionPausesAndResumesWhenHinted() async {
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

    @Test func interruptionWithoutResumeHintStaysPaused() async {
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

    @Test func trackInfoBecomesNowPlayingMetadata() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.emitTrackInfo("Song", "Band")

        #expect(controller.nowPlaying?.title == "Song")
        #expect(controller.nowPlaying?.artist == "Band")
    }

    @Test func staleTrackInfoFromPreviousStreamGenerationIsDropped() async {
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

    @Test func stopResetsToIdle() async {
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

    @Test func onStationPlayedFiresForEveryPlay() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station("a"), station("b")], output: output)

        var played: [String] = []
        controller.onStationPlayed = { played.append($0.id) }

        controller.play(station("a"))
        controller.play(station("b"))
        #expect(played == ["a", "b"])
    }

    // MARK: - Lock-screen (NowPlayingPresenting) contract

    @Test func playingStatusPushesNowPlayingUpdate() async {
        let output = FakeAudioOutput()
        let presenter = NowPlayingPresenterSpy()
        let controller = makeController(stations: [station()], output: output, presenter: presenter)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)

        #expect(presenter.lastUpdate == .update(
            stationID: "kexp", trackTitle: nil, isPlaying: true, artworkURL: nil
        ))
    }

    @Test func pauseDuringLoadingTellsLockScreenNotPlaying() async {
        let output = FakeAudioOutput()
        let presenter = NowPlayingPresenterSpy()
        let controller = makeController(stations: [station()], output: output, presenter: presenter)

        controller.play(station())
        controller.pause()
        await drainMainQueue()

        // The lock screen must reflect the pause even though no player ever started.
        #expect(presenter.lastUpdate == .update(
            stationID: "kexp", trackTitle: nil, isPlaying: false, artworkURL: nil
        ))
    }

    @Test func trackInfoReachesLockScreenWithTitle() async {
        let output = FakeAudioOutput()
        let presenter = NowPlayingPresenterSpy()
        let controller = makeController(stations: [station()], output: output, presenter: presenter)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.emitTrackInfo("Song", "Band")

        #expect(presenter.lastUpdate == .update(
            stationID: "kexp", trackTitle: "Song", isPlaying: true, artworkURL: nil
        ))
    }

    @Test func interruptionTellsLockScreenNotPlaying() async {
        let output = FakeAudioOutput()
        let presenter = NowPlayingPresenterSpy()
        let controller = makeController(stations: [station()], output: output, presenter: presenter)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.onStatusChange?(.interruptionBegan)

        #expect(presenter.lastUpdate == .update(
            stationID: "kexp", trackTitle: nil, isPlaying: false, artworkURL: nil
        ))
        #expect(controller.state == .paused(station()))
    }

    @Test func stopClearsLockScreen() async {
        let output = FakeAudioOutput()
        let presenter = NowPlayingPresenterSpy()
        let controller = makeController(stations: [station()], output: output, presenter: presenter)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        controller.stop()

        #expect(presenter.events.last == .clear)
    }

    @Test func remoteCommandsDriveTheController() async {
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

    @Test func icyMetadataParsesArtistAndTitle() {
        let info = ICYMetadataParser.parseTrack(from: "Radiohead - Weird Fishes")
        #expect(info.artist == "Radiohead")
        #expect(info.title == "Weird Fishes")
    }

    @Test func icyMetadataWithoutSeparatorIsTitleOnly() {
        let info = ICYMetadataParser.parseTrack(from: "Station Jingle")
        #expect(info.artist == nil)
        #expect(info.title == "Station Jingle")
    }

    @Test func icyMetadataSplitsOnFirstSeparatorOnly() {
        let info = ICYMetadataParser.parseTrack(from: "Artist - Title - Live Session")
        #expect(info.artist == "Artist")
        #expect(info.title == "Title - Live Session")
    }

    @Test func icyMetadataWithEmptyArtistIsNil() {
        let info = ICYMetadataParser.parseTrack(from: " - Orphan Title")
        #expect(info.artist == nil)
        #expect(info.title == "Orphan Title")
    }
}
