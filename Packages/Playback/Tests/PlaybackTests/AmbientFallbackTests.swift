import Foundation
import RadioDirectory
import Testing

@testable import Playback

/// The ambient-fallback offer during ad breaks: detection flips
/// `isAdPlaying`, the fallback plays a calm station, and an in-flight lookup
/// must never override what the user (or the stream) did in the meantime.
@MainActor
struct AmbientFallbackTests {
    private func station(
        _ id: String = "kexp",
        name: String? = nil,
        genre: String = "Indie"
    ) -> Station {
        Station(
            id: id,
            name: name ?? "Station \(id)",
            genre: genre,
            listenerCount: 0,
            preferredStreamURL: URL(string: "https://example.com/\(id).aac")
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

    /// Plays the default station until an ad-break marker arrives.
    private func playIntoAdBreak(
        _ controller: PlaybackController,
        output: FakeAudioOutput
    ) async {
        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.onTrackInfo?(AudioTrackInfo(title: nil, artist: nil, isAdvertisement: true))
    }

    @Test func advertisementMetadataClearsTrackAndEnablesAmbientOffer() async {
        let output = FakeAudioOutput()
        let controller = PlaybackController(
            directory: BundledRadioDirectory(stations: [station()]),
            output: output,
            nowPlayingCenter: NowPlayingPresenterSpy()
        )

        await playIntoAdBreak(controller, output: output)

        #expect(controller.isAdPlaying)
        #expect(controller.nowPlaying == nil)

        output.onTrackInfo?(AudioTrackInfo(title: "Song", artist: "Band"))
        #expect(controller.isAdPlaying == false)
        #expect(controller.nowPlaying?.title == "Song")
    }

    @Test func ambientFallbackPlaysAmbientStationDuringAnAd() async {
        let output = FakeAudioOutput()
        let ambient = station("ambient-current", name: "Ambient Current", genre: "Ambient")
        let controller = PlaybackController(
            directory: BundledRadioDirectory(stations: [station(), ambient]),
            output: output,
            nowPlayingCenter: NowPlayingPresenterSpy()
        )

        await playIntoAdBreak(controller, output: output)

        await controller.playAmbientFallback()
        await waitForStart(output, count: 2)

        #expect(controller.currentStation?.id == "ambient-current")
        #expect(output.startedURL?.absoluteString == ambient.preferredStreamURL?.absoluteString)
    }

    @Test func ambientFallbackAbortsWhenAdEndsDuringLookup() async {
        let output = FakeAudioOutput()
        let ambient = station("ambient-current", name: "Ambient Current", genre: "Ambient")
        let directory = GatedRadioDirectory(stations: [station(), ambient])
        let controller = PlaybackController(
            directory: directory,
            output: output,
            nowPlayingCenter: NowPlayingPresenterSpy()
        )

        await playIntoAdBreak(controller, output: output)

        let fallbackTask = Task { await controller.playAmbientFallback() }
        await drainMainQueue()
        // The ad break ends while the directory lookup is still in flight.
        output.onTrackInfo?(AudioTrackInfo(title: "Song", artist: "Band"))
        await directory.open()
        await fallbackTask.value

        #expect(controller.currentStation?.id == "kexp", "the lookup must not hijack resumed programming")
        #expect(output.startedURLs.count == 1)
        #expect(controller.isLoadingAmbientFallback == false)
        #expect(controller.ambientFallbackError == nil)
    }

    @Test func ambientFallbackAbortsWhenPlaybackStoppedDuringLookup() async {
        let output = FakeAudioOutput()
        let ambient = station("ambient-current", name: "Ambient Current", genre: "Ambient")
        let directory = GatedRadioDirectory(stations: [station(), ambient])
        let controller = PlaybackController(
            directory: directory,
            output: output,
            nowPlayingCenter: NowPlayingPresenterSpy()
        )

        await playIntoAdBreak(controller, output: output)

        let fallbackTask = Task { await controller.playAmbientFallback() }
        await drainMainQueue()
        // The user stops playback while the directory lookup is still in flight.
        controller.stop()
        await directory.open()
        await fallbackTask.value

        #expect(controller.state == .idle, "stopped playback must stay stopped")
        #expect(controller.currentStation == nil)
        #expect(output.startedURLs.count == 1)
    }
}
