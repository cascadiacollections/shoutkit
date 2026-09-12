@testable import Playback
import RadioDirectory
import Testing

// Shared builders such as station(_) live in PlaybackTestSupport.swift.

struct PlaybackStateTests {
    @Test(arguments: [
        PlaybackState.loading(station()),
        .buffering(station()),
        .playing(station()),
    ])
    func `exposes handoff station for active playback`(state: PlaybackState) {
        #expect(state.handoffStation == station())
    }

    @Test(arguments: [
        PlaybackState.idle,
        .paused(station()),
        .failed(.noInternet)
    ])
    func `omits handoff station for inactive playback`(state: PlaybackState) {
        #expect(state.handoffStation == nil)
    }
}
