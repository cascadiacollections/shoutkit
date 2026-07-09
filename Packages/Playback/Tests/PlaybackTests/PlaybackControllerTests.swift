import Foundation
import RadioDirectory
import Testing

@testable import Playback

@MainActor
final class FakeAudioOutput: AudioOutput {
    var onStatusChange: ((AudioStatus) -> Void)?
    var onTrackInfo: ((AudioTrackInfo) -> Void)?

    private(set) var startedURLs: [URL] = []
    private(set) var stopCalled = false

    var startedURL: URL? { startedURLs.last }

    func start(url: URL) { startedURLs.append(url) }
    func pause() { onStatusChange?(.paused) }
    func resume() { onStatusChange?(.playing) }
    func stop() { stopCalled = true }
}

/// Spy standing in for the system now-playing surface, so tests never touch
/// `MPRemoteCommandCenter.shared()` and can assert exactly what the lock screen
/// was told, and when.
@MainActor
final class NowPlayingPresenterSpy: NowPlayingPresenting {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onToggle: (() -> Void)?

    enum Event: Equatable {
        case update(stationID: String, trackTitle: String?, isPlaying: Bool, artworkURL: URL?)
        case clear
    }

    private(set) var events: [Event] = []

    var lastUpdate: Event? { events.last(where: { $0 != .clear }) }

    func update(station: Station, track: NowPlayingMetadata?, isPlaying: Bool, artworkURL: URL?) {
        events.append(.update(
            stationID: station.id,
            trackTitle: track?.title,
            isPlaying: isPlaying,
            artworkURL: artworkURL
        ))
    }

    func clear() {
        events.append(.clear)
    }
}

@MainActor
struct PlaybackControllerTests {
    private func station(_ id: String = "kexp") -> Station {
        Station(
            id: id,
            name: "Station \(id)",
            genre: "Indie",
            listenerCount: 0,
            preferredStreamURL: URL(string: "https://example.com/\(id).aac")
        )
    }

    private func makeController(
        stations: [Station],
        output: FakeAudioOutput,
        presenter: NowPlayingPresenterSpy = NowPlayingPresenterSpy()
    ) -> PlaybackController {
        PlaybackController(
            directory: BundledRadioDirectory(stations: stations),
            output: output,
            nowPlayingCenter: presenter
        )
    }

    private func waitForStart(_ output: FakeAudioOutput, count: Int = 1) async {
        for _ in 0..<200 where output.startedURLs.count < count {
            await Task.yield()
        }
    }

    private func drainMainQueue() async {
        for _ in 0..<50 {
            await Task.yield()
        }
    }

    @Test func playResolvesEndpointAndStartsOutput() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        #expect(controller.state == .loading(station()))

        await waitForStart(output)
        #expect(output.startedURL != nil)
        #expect(controller.currentStation?.id == "kexp")
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
        output.onStatusChange?(.interruptionEnded(shouldResume: true))
        #expect(controller.state == .playing(station()))
    }

    @Test func interruptionWithoutResumeHintStaysPaused() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)

        output.onStatusChange?(.interruptionBegan)
        output.onStatusChange?(.interruptionEnded(shouldResume: false))
        #expect(controller.state == .paused(station()))
    }

    @Test func trackInfoBecomesNowPlayingMetadata() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.onTrackInfo?(AudioTrackInfo(title: "Song", artist: "Band"))

        #expect(controller.nowPlaying?.title == "Song")
        #expect(controller.nowPlaying?.artist == "Band")
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
        output.onTrackInfo?(AudioTrackInfo(title: "Song", artist: "Band"))

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

    // MARK: - Album art resolution

    @Test func resolvedAlbumArtIsPublishedAndPushedToLockScreen() async throws {
        let output = FakeAudioOutput()
        let presenter = NowPlayingPresenterSpy()
        let controller = makeController(stations: [station()], output: output, presenter: presenter)
        let art = try #require(URL(string: "https://example.com/art/600x600bb.jpg"))
        controller.albumArtURLProvider = { _ in art }

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.onTrackInfo?(AudioTrackInfo(title: "Song", artist: "Band"))
        await drainMainQueue()

        #expect(controller.albumArtURL == art)
        #expect(presenter.lastUpdate == .update(
            stationID: "kexp", trackTitle: "Song", isPlaying: true, artworkURL: art
        ))
    }

    @Test func duplicateTrackInfoDoesNotRefireLookup() async throws {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)
        let art = try #require(URL(string: "https://example.com/art.jpg"))
        var lookups = 0
        controller.albumArtURLProvider = { _ in
            lookups += 1
            return art
        }

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.onTrackInfo?(AudioTrackInfo(title: "Song", artist: "Band"))
        await drainMainQueue()
        // ICY streams re-deliver identical metadata; it must not churn.
        output.onTrackInfo?(AudioTrackInfo(title: "Song", artist: "Band"))
        await drainMainQueue()

        #expect(lookups == 1)
        #expect(controller.albumArtURL == art)
    }

    @Test func lateArtForPreviousTrackIsDiscarded() async throws {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)
        let oldArt = try #require(URL(string: "https://example.com/old.jpg"))
        let newArt = try #require(URL(string: "https://example.com/new.jpg"))
        controller.albumArtURLProvider = { track in
            if track.title == "Old" {
                // Outlast the track change below; cancellation and the
                // staleness guard must keep this result from applying.
                for _ in 0..<400 { await Task.yield() }
                return oldArt
            }
            return newArt
        }

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.onTrackInfo?(AudioTrackInfo(title: "Old", artist: "Band"))
        output.onTrackInfo?(AudioTrackInfo(title: "New", artist: "Band"))
        for _ in 0..<600 { await Task.yield() }

        #expect(controller.albumArtURL == newArt)
    }

    @Test func stopClearsAlbumArt() async throws {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)
        let art = try #require(URL(string: "https://example.com/art.jpg"))
        controller.albumArtURLProvider = { _ in art }

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.onTrackInfo?(AudioTrackInfo(title: "Song", artist: "Band"))
        await drainMainQueue()
        #expect(controller.albumArtURL == art)

        controller.stop()
        #expect(controller.albumArtURL == nil)
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
