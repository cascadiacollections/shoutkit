import ConcurrencyExtras
import Foundation
@testable import Playback
import Testing

extension MainSerialExecutorTests {
    /// The injected album-art provider seam: resolution reaching the lock screen,
    /// duplicate-push dedupe, staleness, and reset. See `DECISIONS.md` for why
    /// each guard exists.
    @MainActor
    struct PlaybackControllerAlbumArtTests {
        @Test func `resolved album art is published and pushed to lock screen`() async throws {
            try await withMainSerialExecutor {
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
                    stationID: "kexp", trackTitle: "Song", isPlaying: true, artwork: .resolved(art),
                ))
            }
        }

        /// A track boundary used to push the station's own artwork as if it were this
        /// track's, then replace it a lookup later. That is two artwork changes per
        /// song; a Bluetooth head unit is told the track changed and re-fetches cover
        /// art over a slow side channel for each one, and commonly finishes neither.
        /// The boundary now says "resolving" and the verdict push is the only change.
        @Test func `track start holds artwork until the lookup answers`() async throws {
            try await withMainSerialExecutor {
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

                #expect(Array(presenter.artworkPushes.suffix(2)) == [.resolving, .resolved(art)])
            }
        }

        /// The hold has to be bounded, or a track the lookup can't match would keep
        /// the previous track's cover on screen for its whole duration.
        @Test func `lookup miss releases the hold`() async {
            await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let presenter = NowPlayingPresenterSpy()
                let controller = makeController(stations: [station()], output: output, presenter: presenter)
                controller.trackResourcesProvider = { _ in .none }

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.playing)
                output.emitTrackInfo("Song", "Band")
                await drainMainQueue()

                #expect(Array(presenter.artworkPushes.suffix(2)) == [.resolving, .resolved(nil)])
            }
        }

        /// With album art turned off there is no lookup to wait for, so the boundary
        /// must not claim one is running — nothing would ever release the hold.
        @Test func `track start without A provider resolves immediately`() async {
            await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let presenter = NowPlayingPresenterSpy()
                let controller = makeController(stations: [station()], output: output, presenter: presenter)

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.playing)
                output.emitTrackInfo("Song", "Band")
                await drainMainQueue()

                #expect(presenter.artworkPushes.contains(.resolving) == false)
                #expect(presenter.lastUpdate == .update(
                    stationID: "kexp", trackTitle: "Song", isPlaying: true, artwork: .resolved(nil),
                ))
            }
        }

        @Test func `resolved apple music link is published`() async throws {
            try await withMainSerialExecutor {
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
        }

        @Test func `apple music link resolves without artwork`() async throws {
            try await withMainSerialExecutor {
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
        }

        @Test func `duplicate track info does not refire lookup`() async throws {
            try await withMainSerialExecutor {
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
        }

        /// A resolution that produced nothing may have been a transient network
        /// failure (the lookup deliberately doesn't cache those), and the repeated
        /// ICY push is the only retry signal there is — so, unlike a resolved
        /// track, an unresolved one re-runs the lookup on a duplicate push.
        @Test func `duplicate track info retries lookup after empty resolution`() async throws {
            try await withMainSerialExecutor {
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
        }

        /// Engine metadata callbacks are asynchronous, so a previous station's
        /// track info can arrive while the new station's endpoint is still
        /// resolving; it must not be attributed to the new station.
        @Test func `track info before stream start is ignored`() async {
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

        @Test func `stop clears album art`() async throws {
            try await withMainSerialExecutor {
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
        }

        @Test func `on track heard fires for parsed track and resolved link`() async throws {
            try await withMainSerialExecutor {
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
        }
    }
}
