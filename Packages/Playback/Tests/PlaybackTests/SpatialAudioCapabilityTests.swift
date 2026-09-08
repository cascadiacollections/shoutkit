import Foundation
import RadioDirectory
import Testing

@testable import Playback

/// A minimal ``RadioPlaybackEngine`` double for exercising
/// ``PlaybackController/supportsSpatialAudio``/``setSpatialAudioEnabled(_:)``
/// without pulling in AudioStreaming, AVFoundation, or CoreMotion.
@MainActor
private final class FakeRadioPlaybackEngine: RadioPlaybackEngine {
    var onStatusChange: ((AudioStatus) -> Void)?
    var onTrackInfo: ((AudioTrackInfo) -> Void)?
    let supportsSpatialAudio: Bool
    private(set) var spatialAudioStates: [Bool] = []

    init(supportsSpatialAudio: Bool) {
        self.supportsSpatialAudio = supportsSpatialAudio
    }

    func start(url: URL, streamGeneration: UInt64) {}
    func pause() {}
    func resume() {}
    func stop() {}

    func setSpatialAudioEnabled(_ isEnabled: Bool) {
        spatialAudioStates.append(isEnabled)
    }
}

@MainActor
struct SpatialAudioCapabilityTests {
    @Test func plainAudioOutputReportsNoSpatialAudioSupport() {
        let controller = makeController(stations: [station()], output: FakeAudioOutput())
        #expect(controller.supportsSpatialAudio == false)
    }

    @Test func enablingSpatialAudioOnAPlainAudioOutputIsANoOp() {
        let controller = makeController(stations: [station()], output: FakeAudioOutput())
        // Must not crash or throw; there is simply nothing to apply it to.
        controller.setSpatialAudioEnabled(true)
    }

    @Test func engineWithoutSpatialAudioSupportReportsFalse() {
        let engine = FakeRadioPlaybackEngine(supportsSpatialAudio: false)
        let controller = PlaybackController(
            directory: BundledRadioDirectory(stations: [station()]),
            output: engine,
            nowPlayingCenter: NowPlayingPresenterSpy()
        )
        #expect(controller.supportsSpatialAudio == false)
    }

    @Test func engineWithSpatialAudioSupportForwardsTheToggle() {
        let engine = FakeRadioPlaybackEngine(supportsSpatialAudio: true)
        let controller = PlaybackController(
            directory: BundledRadioDirectory(stations: [station()]),
            output: engine,
            nowPlayingCenter: NowPlayingPresenterSpy()
        )
        #expect(controller.supportsSpatialAudio)

        controller.setSpatialAudioEnabled(true)
        controller.restoreSpatialAudioPreference(isEnabled: false)
        #expect(engine.spatialAudioStates == [true, false])
    }
}
