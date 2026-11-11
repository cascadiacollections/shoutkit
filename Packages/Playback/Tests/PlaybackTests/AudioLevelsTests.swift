import AudioLevels
import AVFoundation
import Foundation
@testable import Playback
import RadioDirectory
import Testing

/// A ``RadioPlaybackEngine`` double that accepts tap plug-ins, to check the
/// controller attaches a meter and detaches it when the stream ends.
@MainActor
private final class TappingEngine: RadioPlaybackEngine {
    var onStatusChange: ((AudioStatusUpdate) -> Void)?
    var onTrackInfo: ((AudioTrackInfo) -> Void)?
    private(set) var plugins: [any AudioTapPlugin] = []

    func start(url _: URL, streamGeneration _: UInt64) {}
    func pause() {}
    func resume() {}
    func stop() {}

    var supportsAudioTaps: Bool {
        true
    }

    func addAudioTap(_ plugin: any AudioTapPlugin) {
        plugins.append(plugin)
    }

    func removeAudioTap(_ plugin: any AudioTapPlugin) {
        plugins.removeAll { $0 === plugin }
    }
}

private func toneBuffer() throws -> AVAudioPCMBuffer {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
    buffer.frameLength = 1024
    let data = try #require(buffer.floatChannelData)
    for frame in 0 ..< 1024 {
        data[0][frame] = 0.5 * Float(sin(2 * Double.pi * 1000 * Double(frame) / 44100))
    }
    return buffer
}

@MainActor
struct AudioLevelsCapabilityTests {
    @Test func `plain audio output reports no metering and an empty stream`() async {
        let controller = makeController(stations: [station()], output: FakeAudioOutput())
        #expect(controller.supportsAudioLevels == false)
        var received = 0
        for await _ in controller.audioLevels() {
            received += 1
        }
        #expect(received == 0)
    }

    @Test func `the stub engine does not take taps`() {
        #expect(StubRadioPlaybackEngine().supportsAudioTaps == false)
    }

    @Test func `a meter is attached, fed, and detached when its stream ends`() async throws {
        let engine = TappingEngine()
        let controller = PlaybackController(
            directory: BundledRadioDirectory(stations: [station()]),
            output: engine,
            nowPlayingCenter: NowPlayingPresenterSpy(),
        )
        #expect(controller.supportsAudioLevels)

        var stream: AsyncStream<AudioLevels>? = controller.audioLevels()
        #expect(engine.plugins.count == 1)
        let plugin = try #require(engine.plugins.first)
        try plugin.process(toneBuffer(), at: nil)

        // The consumer owns the only reference, and leaves the loop after one
        // frame without being cancelled — the case that used to leak the tap.
        let consumer = Task { [stream] () -> AudioLevels? in
            guard let stream else { return nil }
            for await levels in stream {
                return levels
            }
            return nil
        }
        stream = nil
        let first = try #require(await consumer.value)
        #expect((first.bands.max() ?? 0) > 0.3)

        // Dropping the stream ends it; detaching hops to the main actor.
        for _ in 0 ..< 50 where engine.plugins.isEmpty == false {
            await Task.yield()
        }
        #expect(engine.plugins.isEmpty)
    }

    @Test func `two consumers get two meters`() {
        let engine = TappingEngine()
        let controller = PlaybackController(
            directory: BundledRadioDirectory(stations: [station()]),
            output: engine,
            nowPlayingCenter: NowPlayingPresenterSpy(),
        )
        _ = controller.audioLevels()
        _ = controller.audioLevels(bandCount: 5)
        #expect(engine.plugins.count == 2)
    }
}
