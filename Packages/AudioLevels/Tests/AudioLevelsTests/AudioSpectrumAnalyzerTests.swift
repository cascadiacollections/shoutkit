@testable import AudioLevels
import AVFoundation
import Foundation
import Testing

/// Builds a buffer holding a sine at `frequency`, in either layout the mixer
/// tap can hand over.
private func sineBuffer(
    frequency: Double,
    amplitude: Float = 0.5,
    sampleRate: Double = 48000,
    frames: Int = 2048,
    channels: AVAudioChannelCount = 2,
    interleaved: Bool = false,
) throws -> AVAudioPCMBuffer {
    let format = try #require(AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: channels,
        interleaved: interleaved,
    ))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
    buffer.frameLength = AVAudioFrameCount(frames)
    let data = try #require(buffer.floatChannelData)
    for frame in 0 ..< frames {
        let value = amplitude * Float(sin(2 * .pi * frequency * Double(frame) / sampleRate))
        for channel in 0 ..< Int(channels) {
            if interleaved {
                data[0][frame * Int(channels) + channel] = value
            } else {
                data[channel][frame] = value
            }
        }
    }
    return buffer
}

private func loudestBand(_ levels: AudioLevels) -> Int? {
    levels.bands.indices.max { levels.bands[$0] < levels.bands[$1] }
}

struct AudioSpectrumAnalyzerTests {
    @Test func `silence reads as zero in every band`() throws {
        let analyzer = try #require(AudioSpectrumAnalyzer())
        let levels = try #require(try analyzer.levels(for: sineBuffer(frequency: 440, amplitude: 0)))
        #expect(levels.bands.count == AudioLevels.defaultBandCount)
        #expect(levels.bands.allSatisfy { $0 == 0 })
    }

    @Test func `a tone peaks in the band that contains it`() throws {
        let analyzer = try #require(AudioSpectrumAnalyzer())
        let levels = try #require(try analyzer.levels(for: sineBuffer(frequency: 1000)))
        let bins = AudioSpectrumAnalyzer.bandBins(
            bandCount: AudioLevels.defaultBandCount,
            frameSize: analyzer.frameSize,
            sampleRate: 48000,
            minimumFrequency: 40,
            maximumFrequency: 16000,
        )
        let toneBin = Int((1000 / (48000 / Float(analyzer.frameSize))).rounded())
        let expected = try #require(bins.firstIndex { $0.contains(toneBin) })
        #expect(loudestBand(levels) == expected)
        // -6 dBFS against a -60 dB floor is ~0.9.
        #expect(levels.bands[expected] > 0.8)
    }

    @Test func `a lower tone lights a lower band`() throws {
        let analyzer = try #require(AudioSpectrumAnalyzer())
        let low = try #require(try analyzer.levels(for: sineBuffer(frequency: 120)))
        let high = try #require(try analyzer.levels(for: sineBuffer(frequency: 6000)))
        let lowBand = try #require(loudestBand(low))
        let highBand = try #require(loudestBand(high))
        #expect(lowBand < highBand)
    }

    @Test func `equal tones read higher in the treble than the bass`() throws {
        let analyzer = try #require(AudioSpectrumAnalyzer())
        let bass = try #require(try analyzer.levels(for: sineBuffer(frequency: 200, amplitude: 0.05)))
        let treble = try #require(try analyzer.levels(for: sineBuffer(frequency: 8000, amplitude: 0.05)))
        let bassPeak = try #require(bass.bands.max())
        let treblePeak = try #require(treble.bands.max())
        #expect(treblePeak > bassPeak)
    }

    @Test func `interleaved and deinterleaved buffers read the same`() throws {
        let analyzer = try #require(AudioSpectrumAnalyzer())
        let planar = try #require(try analyzer.levels(for: sineBuffer(frequency: 2500)))
        let interleaved = try #require(try analyzer.levels(for: sineBuffer(frequency: 2500, interleaved: true)))
        for (lhs, rhs) in zip(planar.bands, interleaved.bands) {
            #expect(abs(lhs - rhs) < 0.0001)
        }
    }

    @Test func `a buffer shorter than a frame is zero padded rather than rejected`() throws {
        let analyzer = try #require(AudioSpectrumAnalyzer())
        let levels = try analyzer.levels(for: sineBuffer(frequency: 1000, frames: 300))
        #expect(levels != nil)
    }

    @Test func `every band covers at least one bin and bands never overlap`() {
        let bins = AudioSpectrumAnalyzer.bandBins(
            bandCount: 24,
            frameSize: 1024,
            sampleRate: 44100,
            minimumFrequency: 40,
            maximumFrequency: 16000,
        )
        #expect(bins.count == 24)
        #expect(bins.allSatisfy { $0.isEmpty == false && $0.upperBound <= 512 })
        for (lower, upper) in zip(bins, bins.dropFirst()) {
            #expect(lower.upperBound <= upper.lowerBound)
        }
    }

    @Test func `an unsupported frame size fails construction`() {
        #expect(AudioSpectrumAnalyzer(frameSize: 1000) == nil)
    }
}

struct AudioLevelMeterTests {
    @Test func `frames closer together than the interval are dropped`() throws {
        let meter = try #require(AudioLevelMeter(minimumInterval: .milliseconds(33)))
        let buffer = try sineBuffer(frequency: 1000)
        let start = ContinuousClock.now
        #expect(meter.measure(buffer, at: start) != nil)
        #expect(meter.measure(buffer, at: start + .milliseconds(10)) == nil)
        #expect(meter.measure(buffer, at: start + .milliseconds(40)) != nil)
    }

    @Test func `levels rise quickly and fall slowly`() {
        let risen = AudioLevelMeter.smooth(previous: [0], next: [1])[0]
        let fallen = AudioLevelMeter.smooth(previous: [1], next: [0])[0]
        #expect(risen == AudioLevelMeter.attack)
        #expect(1 - fallen == AudioLevelMeter.release)
        #expect(risen > 1 - fallen)
    }
}
