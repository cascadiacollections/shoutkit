import Foundation
@testable import Playback
import Testing

/// Ported verbatim from the Android client's `EqualizerCurvesTest`
/// (core/playback in sir-android) so both clients' curve math is verified
/// identically.
struct EqualizerCurvesTests {
    private let minGain: Float = -15
    private let maxGain: Float = 15

    private func levels(_ preset: EqualizerPreset, bands: Int = 5) -> [Float] {
        EqualizerCurves.levels(for: preset, bandCount: bands, minGain: minGain, maxGain: maxGain)
    }

    @Test func `normal preset is flat at zero`() {
        #expect(levels(.normal) == Array(repeating: 0, count: 5))
    }

    @Test func `normal preset stays flat for asymmetric ranges`() {
        let asymmetric = EqualizerCurves.levels(for: .normal, bandCount: 5, minGain: -12, maxGain: 4)
        #expect(asymmetric == Array(repeating: 0, count: 5))
    }

    @Test func `bass boost is non increasing across bands`() {
        let result = levels(.bassBoost)
        for (lower, higher) in zip(result, result.dropFirst()) {
            #expect(higher <= lower)
        }
        #expect(result[0] > result[4])
    }

    @Test func `treble boost is non decreasing across bands`() {
        let result = levels(.treble)
        for (lower, higher) in zip(result, result.dropFirst()) {
            #expect(higher >= lower)
        }
        #expect(result[4] > result[0])
    }

    @Test func `vocal preset peaks in mid bands`() {
        let result = levels(.vocal)
        #expect(result[2] > result[0])
        #expect(result[2] > result[4])
    }

    @Test func `levels never escape the supported range`() {
        for preset in EqualizerPreset.allCases {
            for value in levels(preset, bands: 10) {
                #expect(value >= minGain && value <= maxGain)
            }
        }
    }

    @Test func `single band uses position zero`() {
        let result = EqualizerCurves.levels(
            bandCount: 1,
            minGain: minGain,
            maxGain: maxGain,
            range: 30,
            curve: { 1 - $0 },
        )
        #expect(result == [15])
    }

    @Test func `curve output above one clamps to max gain`() {
        let result = EqualizerCurves.levels(
            bandCount: 5,
            minGain: minGain,
            maxGain: maxGain,
            range: 30,
            curve: { _ in 2 },
        )
        #expect(result.allSatisfy { $0 == maxGain })
    }

    @Test func `curve overshooting the range clamps to the nearest rail`() {
        let high = EqualizerCurves.levels(bandCount: 1, minGain: 0, maxGain: 1000, range: 1000, curve: { _ in 40 })
        #expect(high == [1000])
    }

    @Test func `curve undershooting the range clamps to the lower rail`() {
        let low = EqualizerCurves.levels(bandCount: 1, minGain: 0, maxGain: 1000, range: 1000, curve: { _ in -40 })
        #expect(low == [0])
    }
}
