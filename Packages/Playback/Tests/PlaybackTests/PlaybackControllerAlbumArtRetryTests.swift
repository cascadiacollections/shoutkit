import ConcurrencyExtras
import Foundation
@testable import Playback
import Testing

extension MainSerialExecutorTests {
    /// Split from `PlaybackControllerAlbumArtTests` so that file stays inside
    /// SwiftLint's `type_body_length` limit. Same doubles, same contract.
    @MainActor
    struct PlaybackControllerAlbumArtRetryTests {
        /// A miss still retries the lookup. It must not publish again: each
        /// publication writes listening history, and the title repeats for the
        /// whole song.
        @Test func `repeated misses do not republish history or artwork`() async {
            await withMainSerialExecutor {
                let output = FakeAudioOutput()
                let presenter = NowPlayingPresenterSpy()
                let controller = makeController(stations: [station()], output: output, presenter: presenter)
                var lookups = 0
                var heard = 0
                controller.trackResourcesProvider = { _ in
                    lookups += 1
                    return .none
                }
                controller.onTrackHeard = { _ in heard += 1 }

                controller.play(station())
                await waitForStart(output)
                output.onStatusChange?(.playing)
                output.emitTrackInfo("Song", "Band")
                await drainMainQueue()
                let pushes = presenter.events.count
                #expect(lookups == 1)
                #expect(heard == 2)

                output.emitTrackInfo("Song", "Band")
                await drainMainQueue()

                #expect(lookups == 2)
                #expect(heard == 2)
                #expect(presenter.events.count == pushes)
                #expect(presenter.lastUpdate == .update(
                    stationID: "kexp", trackTitle: "Song", isPlaying: true, artwork: .resolved(nil),
                ))
            }
        }
    }
}
