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
        controller.trackResourcesProvider = { _ in TrackResources(artworkURL: art) }

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.emitTrackInfo("Song", "Band")
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
        output.emitTrackInfo("Song", "Band")
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
        output.emitTrackInfo("Song", "Band")
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
        output.emitTrackInfo("Song", "Band")
        await drainMainQueue()
        // ICY streams re-deliver identical metadata; it must not churn.
        output.emitTrackInfo("Song", "Band")
        await drainMainQueue()

        #expect(lookups == 1)
        #expect(controller.albumArtURL == art)
    }

    // A resolution that produced nothing may have been a transient network
    // failure (the lookup deliberately doesn't cache those), and the repeated
    // ICY push is the only retry signal there is — so, unlike a resolved
    // track, an unresolved one re-runs the lookup on a duplicate push.
    @Test func duplicateTrackInfoRetriesLookupAfterEmptyResolution() async throws {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)
        let art = try #require(URL(string: "https://example.com/art.jpg"))
        var lookups = 0
        controller.trackResourcesProvider = { _ in
            lookups += 1
            return lookups == 1 ? .none : TrackResources(artworkURL: art)
        }

        controller.play(station())
        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.emitTrackInfo("Song", "Band")
        await drainMainQueue()
        #expect(lookups == 1)
        #expect(controller.albumArtURL == nil)

        output.emitTrackInfo("Song", "Band")
        await drainMainQueue()

        #expect(lookups == 2)
        #expect(controller.albumArtURL == art)
    }

    // Engine metadata callbacks are asynchronous, so a previous station's
    // track info can arrive while the new station's endpoint is still
    // resolving; it must not be attributed to the new station.
    @Test func trackInfoBeforeStreamStartIsIgnored() async {
        let output = FakeAudioOutput()
        let controller = makeController(stations: [station()], output: output)

        controller.play(station())
        output.onTrackInfo?(AudioTrackInfo(title: "Stale Song", artist: "Stale Band"))
        #expect(controller.nowPlaying == nil)

        await waitForStart(output)
        output.onStatusChange?(.playing)
        output.emitTrackInfo("Song", "Band")
        #expect(controller.nowPlaying?.title == "Song")
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
        output.emitTrackInfo("Old", "Band")
        output.emitTrackInfo("New", "Band")
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
        output.emitTrackInfo("Song", "Band")
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
        output.emitTrackInfo("Song", "Band")
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
        output.emitTrackInfo("Old", "Band")
        await drainMainQueue()
        #expect(controller.albumArtURL == oldArt)

        // `observeChanges` re-enters on MainActor, so these callbacks append in
        // the same serialized order the properties publish changes.
        var events: [String] = []
        let albumArtObservation = observeChanges(of: { controller.albumArtURL }, onChange: { url in
            events.append("art:\(url?.absoluteString ?? "nil")")
        })
        let metadataObservation = observeChanges(of: { controller.nowPlaying?.title }, onChange: { title in
            events.append("track:\(title ?? "nil")")
        })
        defer {
            albumArtObservation.cancel()
            metadataObservation.cancel()
        }

        output.emitTrackInfo("New", "Band")
        await waitUntil({ events.count >= 2 })

        #expect(Array(events.prefix(2)) == [
            "art:nil",
            "track:New"
        ])
    }
}
