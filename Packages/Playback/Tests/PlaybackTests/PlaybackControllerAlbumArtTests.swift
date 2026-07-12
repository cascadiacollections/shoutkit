import Foundation
import Observation
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
        controller.trackResourcesProvider = { _ in TrackResources(artworkURL: art) }

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

    @Test func resolvedAppleMusicLinkIsPublished() async throws {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)
        let art = try #require(URL(string: "https://example.com/art.jpg"))
        let link = try #require(URL(string: "https://music.apple.com/us/album/song/1?i=2"))
        controller.trackResourcesProvider = { _ in
            TrackResources(artworkURL: art, appleMusicURL: link)
        }

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.onTrackInfo?(AudioTrackInfo(title: "Song", artist: "Band"))
        await drainMainQueue()

        #expect(controller.appleMusicURL == link)
    }

    @Test func appleMusicLinkResolvesWithoutArtwork() async throws {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)
        let link = try #require(URL(string: "https://music.apple.com/us/album/song/1?i=2"))
        controller.trackResourcesProvider = { _ in TrackResources(appleMusicURL: link) }

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.onTrackInfo?(AudioTrackInfo(title: "Song", artist: "Band"))
        await drainMainQueue()

        #expect(controller.albumArtURL == nil)
        #expect(controller.appleMusicURL == link)
    }

    @Test func duplicateTrackInfoDoesNotRefireLookup() async throws {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)
        let art = try #require(URL(string: "https://example.com/art.jpg"))
        var lookups = 0
        controller.trackResourcesProvider = { _ in
            lookups += 1
            return TrackResources(artworkURL: art)
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
        controller.trackResourcesProvider = { track in
            if track.title == "Old" {
                // Outlast the track change below; cancellation and the
                // staleness guard must keep this result from applying.
                for _ in 0..<400 { await Task.yield() }
                return TrackResources(artworkURL: oldArt)
            }
            return TrackResources(artworkURL: newArt)
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
        let link = try #require(URL(string: "https://music.apple.com/us/album/song/1?i=2"))
        controller.trackResourcesProvider = { _ in
            TrackResources(artworkURL: art, appleMusicURL: link)
        }

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.onTrackInfo?(AudioTrackInfo(title: "Song", artist: "Band"))
        await drainMainQueue()
        #expect(controller.albumArtURL == art)
        #expect(controller.appleMusicURL == link)

        controller.stop()
        #expect(controller.albumArtURL == nil)
        #expect(controller.appleMusicURL == nil)
    }

    @Test func onTrackHeardFiresForParsedTrackAndResolvedLink() async throws {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)
        let link = try #require(URL(string: "https://music.apple.com/us/album/song/1?i=2"))
        controller.trackResourcesProvider = { _ in TrackResources(appleMusicURL: link) }

        var events: [HeardTrack] = []
        controller.onTrackHeard = { events.append($0) }

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.onTrackInfo?(AudioTrackInfo(title: "Song", artist: "Band"))
        await drainMainQueue()

        #expect(events.count == 2)
        #expect(events[0].track.title == "Song")
        #expect(events[0].track.artist == "Band")
        #expect(events[0].appleMusicURL == nil)
        #expect(events[1].appleMusicURL == link)
    }

    @Test func trackChangeClearsPublishedArtworkBeforePublishingNewMetadata() async throws {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)
        let oldArt = try #require(URL(string: "https://example.com/old.jpg"))
        let newArt = try #require(URL(string: "https://example.com/new.jpg"))
        controller.trackResourcesProvider = { track in
            if track.title == "New" {
                for _ in 0..<200 { await Task.yield() }
                return TrackResources(artworkURL: newArt)
            }
            return TrackResources(artworkURL: oldArt)
        }

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.onTrackInfo?(AudioTrackInfo(title: "Old", artist: "Band"))
        await drainMainQueue()
        #expect(controller.albumArtURL == oldArt)

        var events: [String] = []
        let albumArtChanges = Observations { controller.albumArtURL }
        let metadataChanges = Observations { controller.nowPlaying?.title }
        let albumArtTask = Task { @MainActor in
            var skippedInitial = false
            for await url in albumArtChanges {
                if skippedInitial == false {
                    skippedInitial = true
                    continue
                }
                events.append("art:\(url?.absoluteString ?? "nil")")
                if events.count >= 2 { return }
            }
        }
        let metadataTask = Task { @MainActor in
            var skippedInitial = false
            for await title in metadataChanges {
                if skippedInitial == false {
                    skippedInitial = true
                    continue
                }
                events.append("track:\(title ?? "nil")")
                if events.count >= 2 { return }
            }
        }
        defer {
            albumArtTask.cancel()
            metadataTask.cancel()
        }

        await Task.yield()
        output.onTrackInfo?(AudioTrackInfo(title: "New", artist: "Band"))
        await waitUntil({ events.count >= 2 })

        #expect(Array(events.prefix(2)) == [
            "art:nil",
            "track:New"
        ])
    }
}
