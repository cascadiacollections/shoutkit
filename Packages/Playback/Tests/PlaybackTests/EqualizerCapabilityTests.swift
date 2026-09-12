import Foundation
@testable import Playback
import RadioDirectory
import Testing

/// A minimal ``RadioPlaybackEngine`` double for exercising
/// ``PlaybackController/supportsEqualizer``/``setEqualizerPreset(_:)`` without
/// pulling in AudioStreaming or AVFoundation.
@MainActor
private final class FakeRadioPlaybackEngine: RadioPlaybackEngine {
    var onStatusChange: ((AudioStatus) -> Void)?
    var onTrackInfo: ((AudioTrackInfo) -> Void)?
    let supportsEqualizer: Bool
    private(set) var appliedPresets: [EqualizerPreset] = []

    init(supportsEqualizer: Bool) {
        self.supportsEqualizer = supportsEqualizer
    }

    func start(url _: URL, streamGeneration _: UInt64) {}
    func pause() {}
    func resume() {}
    func stop() {}

    func setEqualizerPreset(_ preset: EqualizerPreset) {
        appliedPresets.append(preset)
    }
}

@MainActor
struct EqualizerCapabilityTests {
    @Test func `plain audio output reports no equalizer support`() {
        let controller = makeController(stations: [station()], output: FakeAudioOutput())
        #expect(controller.supportsEqualizer == false)
    }

    @Test func `setting A preset on A plain audio output is A no op`() {
        let controller = makeController(stations: [station()], output: FakeAudioOutput())
        // Must not crash or throw; there is simply nothing to apply it to.
        controller.setEqualizerPreset(.bassBoost)
    }

    @Test func `engine without equalizer support reports false`() {
        let engine = FakeRadioPlaybackEngine(supportsEqualizer: false)
        let controller = PlaybackController(
            directory: BundledRadioDirectory(stations: [station()]),
            output: engine,
            nowPlayingCenter: NowPlayingPresenterSpy(),
        )
        #expect(controller.supportsEqualizer == false)
    }

    @Test func `engine with equalizer support applies the preset`() {
        let engine = FakeRadioPlaybackEngine(supportsEqualizer: true)
        let controller = PlaybackController(
            directory: BundledRadioDirectory(stations: [station()]),
            output: engine,
            nowPlayingCenter: NowPlayingPresenterSpy(),
        )
        #expect(controller.supportsEqualizer)

        controller.setEqualizerPreset(.treble)
        #expect(engine.appliedPresets == [.treble])
    }
}
