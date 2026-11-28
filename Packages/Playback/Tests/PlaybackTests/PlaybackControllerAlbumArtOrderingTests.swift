import ConcurrencyExtras
import Foundation
@testable import Playback
import Testing

/// Split from `PlaybackControllerAlbumArtTests` so that file stays inside
/// SwiftLint's `type_body_length` limit. These two hold a lookup open on a
/// `Gate` and check what publishes, and in what order, while it is held and
/// after it lands.
extension MainSerialExecutorTests {
    @MainActor
    struct PlaybackControllerAlbumArtOrderingTests {
        @Test func `late art for previous track is discarded`() async throws {
            try await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let controller = makeController(stations: [station()], output: output)
                let oldArt = try #require(URL(string: "https://example.com/old.jpg"))
                let newArt = try #require(URL(string: "https://example.com/new.jpg"))
                let oldLookup = Gate()
                controller.trackResourcesProvider = { track in
                    if track.title == "Old" {
                        // Held until the track change below has resolved;
                        // cancellation and the staleness guard must keep this
                        // result from applying when it finally lands.
                        await oldLookup.wait()
                        return TrackResources(artworkURL: oldArt)
                    }
                    return TrackResources(artworkURL: newArt)
                }

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.playing)
                output.emitTrackInfo("Old", "Band")
                output.emitTrackInfo("New", "Band")
                await drainMainQueue()
                #expect(controller.albumArtURL == newArt)

                oldLookup.open()
                await drainMainQueue()
                #expect(controller.albumArtURL == newArt)
            }
        }

        @Test func `track change clears published artwork before publishing new metadata`() async throws {
            try await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let controller = makeController(stations: [station()], output: output)
                let oldArt = try #require(URL(string: "https://example.com/old.jpg"))
                let newArt = try #require(URL(string: "https://example.com/new.jpg"))
                let newLookup = Gate()
                controller.trackResourcesProvider = { track in
                    if track.title == "New" {
                        // Held so the new art cannot publish before the order
                        // below is checked.
                        await newLookup.wait()
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
                await drainMainQueue()

                #expect(events == [
                    "art:nil",
                    "track:New",
                ])

                newLookup.open()
                await drainMainQueue()
                #expect(controller.albumArtURL == newArt)
            }
        }
    }
}
