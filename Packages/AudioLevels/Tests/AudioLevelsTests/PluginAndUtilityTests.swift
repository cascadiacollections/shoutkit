@testable import AudioLevels
import AVFoundation
import Foundation
import Testing

private final class RecordingPlugin: AudioTapPlugin, @unchecked Sendable {
    private let lock = NSLock()
    private var _frameLengths: [AVAudioFrameCount] = []

    var frameLengths: [AVAudioFrameCount] {
        lock.withLock { _frameLengths }
    }

    func process(_ buffer: AVAudioPCMBuffer, at _: AVAudioTime?) {
        lock.withLock { _frameLengths.append(buffer.frameLength) }
    }
}

private func emptyBuffer(frames: AVAudioFrameCount = 256) throws -> AVAudioPCMBuffer {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames
    return buffer
}

struct AudioTapPluginSetTests {
    @Test func `dispatch reaches every plugin and removal stops it`() throws {
        let set = AudioTapPluginSet()
        let first = RecordingPlugin()
        let second = RecordingPlugin()
        set.add(first)
        set.add(second)
        set.add(first)
        #expect(set.count == 2)

        try set.dispatch(emptyBuffer(), at: nil)
        set.remove(first)
        try set.dispatch(emptyBuffer(frames: 128), at: nil)

        #expect(first.frameLengths == [256])
        #expect(second.frameLengths == [256, 128])
        set.remove(second)
        #expect(set.isEmpty)
    }
}

struct AudioLevelMeterStreamTests {
    @Test func `a processed buffer is published on the stream`() async throws {
        let meter = try #require(AudioLevelMeter(minimumInterval: .zero))
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        buffer.frameLength = 1024
        let data = try #require(buffer.floatChannelData)
        for frame in 0 ..< 1024 {
            data[0][frame] = 0.5 * Float(sin(2 * Double.pi * 1000 * Double(frame) / 48000))
        }
        meter.process(buffer, at: nil)
        meter.finish()
        var frames: [AudioLevels] = []
        for await frame in meter.levels {
            frames.append(frame)
        }
        #expect(frames.count == 1)
        #expect((frames.first?.bands.max() ?? 0) > 0.5)
    }

    @Test func `termination handler runs when the stream ends`() async throws {
        let meter = try #require(AudioLevelMeter())
        let (signal, fired) = AsyncStream.makeStream(of: Void.self)
        meter.onTermination { fired.yield() }
        meter.finish()
        var iterator = signal.makeAsyncIterator()
        #expect(await iterator.next() != nil)
    }
}

struct PeakHoldTests {
    @Test func `peaks jump up, hold, then fall at the fall rate`() {
        var hold = PeakHold(bandCount: 1)
        let start = ContinuousClock.now
        hold.update(with: AudioLevels(bands: [0.8]), at: start)
        #expect(hold.peaks == [0.8])

        hold.update(with: AudioLevels(bands: [0.1]), at: start + .milliseconds(500))
        #expect(hold.peaks == [0.8])

        hold.update(with: AudioLevels(bands: [0.1]), at: start + .milliseconds(700))
        #expect(abs(hold.peaks[0] - (0.8 - PeakHold.fallRate * 0.2)) < 0.0001)

        hold.update(with: AudioLevels(bands: [0.1]), at: start + .seconds(5))
        #expect(hold.peaks == [0.1])
    }

    @Test func `a change in band count resets the caps`() {
        var hold = PeakHold(bandCount: 2)
        hold.update(with: AudioLevels(bands: [0.5, 0.5]))
        hold.update(with: AudioLevels(bands: [0.2, 0.2, 0.2]))
        #expect(hold.peaks == [0.2, 0.2, 0.2])
    }
}

struct ResampleTests {
    @Test func `folding keeps the loudest band in each group`() {
        let levels = AudioLevels(bands: [0.1, 0.9, 0.2, 0.3, 0.8, 0.0])
        #expect(levels.resampled(to: 3).bands == [0.9, 0.3, 0.8])
        #expect(levels.resampled(to: 6) == levels)
        #expect(levels.resampled(to: 0).bands.isEmpty)
        #expect(AudioLevels.silent().resampled(to: 5).bands.count == 5)
    }
}

struct MonoEntryPointTests {
    @Test func `mono samples and an equivalent buffer read the same`() throws {
        let analyzer = try #require(AudioSpectrumAnalyzer())
        let samples = (0 ..< 1024).map { Float(0.3 * sin(2 * Double.pi * 440 * Double($0) / 44100)) }
        let mono = try #require(analyzer.levels(forMono: samples, sampleRate: 44100))
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        buffer.frameLength = 1024
        let data = try #require(buffer.floatChannelData)
        for (index, sample) in samples.enumerated() {
            data[0][index] = sample
        }
        let fromBuffer = try #require(analyzer.levels(for: buffer))
        #expect(mono == fromBuffer)
        #expect(analyzer.levels(forMono: [], sampleRate: 44100) == nil)
    }
}

struct AutoGainTests {
    @Test func `quiet material is lifted but never past the floor reference`() {
        var gain = AutoGain()
        let start = ContinuousClock.now
        let quiet = gain.apply(to: AudioLevels(bands: [0.15, 0.06]), at: start)
        #expect(abs(quiet.bands[0] - 0.5) < 0.0001)
        #expect(gain.reference == AutoGain.minimumReference)
    }

    @Test func `a loud frame fills the meter, then the reference decays slowly`() {
        var gain = AutoGain()
        let start = ContinuousClock.now
        let loud = gain.apply(to: AudioLevels(bands: [0.8, 0.4]), at: start)
        #expect(loud.bands == [1, 0.5])

        _ = gain.apply(to: AudioLevels(bands: [0.2]), at: start + .seconds(1))
        #expect(abs(gain.reference - (0.8 - AutoGain.decayRate)) < 0.0001)

        _ = gain.apply(to: AudioLevels(bands: [0.2]), at: start + .seconds(10))
        #expect(gain.reference == AutoGain.minimumReference)
    }

    @Test func `silence stays silent`() {
        var gain = AutoGain()
        #expect(gain.apply(to: .silent()).bands.allSatisfy { $0 == 0 })
    }
}
