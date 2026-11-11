@testable import AudioLevels
import Foundation
import Testing

/// The spec's golden vectors (docs/audio-levels-spec.md, "Golden vectors").
/// Each input is defined by formula rather than stored samples, so any platform
/// can rebuild it exactly; the expected bands are this implementation's output,
/// which is the reference. The Android client checks the same file.
///
/// To regenerate after an intentional spec change:
///
///     AUDIOLEVELS_WRITE_GOLDEN=$PWD/Tests/AudioLevelsTests/Resources/golden-vectors.json \
///       swift test --disable-xctest --filter GoldenVectorTests
struct GoldenVector: Codable {
    struct Tone: Codable {
        let frequency: Double
        let amplitude: Double
    }

    let name: String
    let sampleRate: Double
    let frames: Int
    let tones: [Tone]
    /// Amplitude of the spec's LCG noise source; `0` for none.
    let noiseAmplitude: Double
    var expected: [Float]

    /// `amplitude * sin(2π f n / sampleRate)` summed over tones, plus
    /// `noiseAmplitude * u` where `u` comes from the LCG
    /// `x = (1664525 x + 1013904223) mod 2³²`, seed 1, mapped to `[-1, 1)` as
    /// `x / 2³¹ - 1`. Computed in Double, stored as Float.
    func samples() -> [Float] {
        var state: UInt32 = 1
        return (0 ..< frames).map { frame in
            var value = tones.reduce(0.0) { sum, tone in
                sum + tone.amplitude * sin(2 * .pi * tone.frequency * Double(frame) / sampleRate)
            }
            if noiseAmplitude > 0 {
                state = state &* 1_664_525 &+ 1_013_904_223
                value += noiseAmplitude * (Double(state) / 2_147_483_648 - 1)
            }
            return Float(value)
        }
    }
}

struct GoldenFile: Codable {
    struct Smoothing: Codable {
        let inputs: [Float]
        var expected: [Float]
    }

    let tolerance: Float
    var vectors: [GoldenVector]
    var smoothing: Smoothing
}

private let caseDefinitions: [GoldenVector] = [
    .init(name: "silence", sampleRate: 44100, frames: 1024, tones: [], noiseAmplitude: 0, expected: []),
    .init(name: "sine-1k-half-48k", sampleRate: 48000, frames: 1024,
          tones: [.init(frequency: 1000, amplitude: 0.5)], noiseAmplitude: 0, expected: []),
    .init(name: "sine-120-half-44k1", sampleRate: 44100, frames: 1024,
          tones: [.init(frequency: 120, amplitude: 0.5)], noiseAmplitude: 0, expected: []),
    .init(name: "sine-6k-quarter-44k1", sampleRate: 44100, frames: 1024,
          tones: [.init(frequency: 6000, amplitude: 0.25)], noiseAmplitude: 0, expected: []),
    .init(name: "two-tones-44k1", sampleRate: 44100, frames: 1024,
          tones: [.init(frequency: 200, amplitude: 0.3), .init(frequency: 3000, amplitude: 0.3)],
          noiseAmplitude: 0, expected: []),
    .init(name: "short-buffer-zero-padded", sampleRate: 48000, frames: 300,
          tones: [.init(frequency: 1000, amplitude: 0.5)], noiseAmplitude: 0, expected: []),
    .init(name: "long-buffer-newest-frames", sampleRate: 44100, frames: 4410,
          tones: [.init(frequency: 2500, amplitude: 0.4)], noiseAmplitude: 0, expected: []),
    .init(name: "lcg-noise-tenth", sampleRate: 44100, frames: 1024, tones: [], noiseAmplitude: 0.1, expected: []),
]

private let smoothingInputs: [Float] = [1, 1, 0, 0, 0, 0.5, 0.5, 0.2]

private func smoothed(_ inputs: [Float]) -> [Float] {
    var level: Float = 0
    return inputs.map { input in
        level = AudioLevelMeter.smooth(previous: [level], next: [input])[0]
        return level
    }
}

private func computeGoldenFile() throws -> GoldenFile {
    let vectors = try caseDefinitions.map { definition in
        let analyzer = try #require(AudioSpectrumAnalyzer())
        var vector = definition
        vector.expected = try #require(analyzer.levels(
            forMono: definition.samples(),
            sampleRate: definition.sampleRate,
        )).bands
        return vector
    }
    return GoldenFile(
        tolerance: 0.01,
        vectors: vectors,
        smoothing: .init(inputs: smoothingInputs, expected: smoothed(smoothingInputs)),
    )
}

struct GoldenVectorTests {
    @Test func `the analyzer reproduces every golden vector`() throws {
        let computed = try computeGoldenFile()
        if let path = ProcessInfo.processInfo.environment["AUDIOLEVELS_WRITE_GOLDEN"] {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(computed).write(to: URL(fileURLWithPath: path))
        }
        let url = try #require(Bundle.module.url(forResource: "golden-vectors", withExtension: "json"))
        let golden = try JSONDecoder().decode(GoldenFile.self, from: Data(contentsOf: url))
        #expect(golden.vectors.map(\.name) == computed.vectors.map(\.name))
        for (stored, fresh) in zip(golden.vectors, computed.vectors) {
            #expect(stored.expected.count == AudioLevels.defaultBandCount, "\(stored.name)")
            for (band, (lhs, rhs)) in zip(stored.expected, fresh.expected).enumerated() {
                #expect(abs(lhs - rhs) <= golden.tolerance, "\(stored.name) band \(band)")
            }
        }
        for (lhs, rhs) in zip(golden.smoothing.expected, computed.smoothing.expected) {
            #expect(abs(lhs - rhs) <= 0.0001)
        }
    }
}
