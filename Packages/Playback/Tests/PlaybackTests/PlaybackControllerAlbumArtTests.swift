import Foundation
import Testing

@testable import Playback

/// The injected album-art provider seam: resolution reaching the lock screen,
/// duplicate-push dedupe, staleness, and reset. See `DECISIONS.md` for why
/// each guard exists.
@MainActor
struct PlaybackControllerAlbumArtTests {
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
}
