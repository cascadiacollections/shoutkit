import RadioDirectory
import Testing

@testable import Playback

struct PlaybackStateTests {
    @Test(arguments: [
        PlaybackState.loading(station()),
        .buffering(station()),
        .playing(station())
    ])
    func exposesHandoffStationForActivePlayback(state: PlaybackState) {
        #expect(state.handoffStation == station())
    }

    @Test(arguments: [
        PlaybackState.idle,
        .paused(station()),
        .failed(.noInternet)
    ])
    func omitsHandoffStationForInactivePlayback(state: PlaybackState) {
        #expect(state.handoffStation == nil)
    }
}
