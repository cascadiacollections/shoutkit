import Foundation
import Testing

@testable import Playback

// Ported verbatim from the Android client's `EqualizerCurvesTest`
// (core/playback in sir-android) so both clients' curve math is verified
// identically.
struct EqualizerCurvesTests {
    private let minGain: Float = -15
    private let maxGain: Float = 15

    private func levels(_ preset: EqualizerPreset, bands: Int = 5) -> [Float] {
        EqualizerCurves.levels(for: preset, bandCount: bands, minGain: minGain, maxGain: maxGain)
    }

    @Test func normalPresetIsFlatAtZero() {
        #expect(levels(.normal) == Array(repeating: 0, count: 5))
    }

    @Test func normalPresetStaysFlatForAsymmetricRanges() {
        let asymmetric = EqualizerCurves.levels(for: .normal, bandCount: 5, minGain: -12, maxGain: 4)
        #expect(asymmetric == Array(repeating: 0, count: 5))
    }

    @Test func bassBoostIsNonIncreasingAcrossBands() {
        let result = levels(.bassBoost)
        for (a, b) in zip(result, result.dropFirst()) {
            #expect(b <= a)
        }
        #expect(result.first! > result.last!)
    }

    @Test func trebleBoostIsNonDecreasingAcrossBands() {
        let result = levels(.treble)
        for (a, b) in zip(result, result.dropFirst()) {
            #expect(b >= a)
        }
        #expect(result.last! > result.first!)
    }

    @Test func vocalPresetPeaksInMidBands() {
        let result = levels(.vocal)
        #expect(result[2] > result[0])
        #expect(result[2] > result[4])
    }

    @Test func levelsNeverEscapeTheSupportedRange() {
        for preset in EqualizerPreset.allCases {
            for value in levels(preset, bands: 10) {
                #expect(value >= minGain && value <= maxGain)
            }
        }
    }

    @Test func singleBandUsesPositionZero() {
        let result = EqualizerCurves.levels(
            bandCount: 1,
            minGain: minGain,
            maxGain: maxGain,
            range: 30,
            curve: { 1 - $0 }
        )
        #expect(result == [15])
    }

    @Test func curveOutputAboveOneClampsToMaxGain() {
        let result = EqualizerCurves.levels(bandCount: 5, minGain: minGain, maxGain: maxGain, range: 30, curve: { _ in 2 })
        #expect(result.allSatisfy { $0 == maxGain })
    }

    @Test func curveOvershootingTheRangeClampsToTheNearestRail() {
        let high = EqualizerCurves.levels(bandCount: 1, minGain: 0, maxGain: 1000, range: 1000, curve: { _ in 40 })
        #expect(high == [1000])
    }

    @Test func curveUndershootingTheRangeClampsToTheLowerRail() {
        let low = EqualizerCurves.levels(bandCount: 1, minGain: 0, maxGain: 1000, range: 1000, curve: { _ in -40 })
        #expect(low == [0])
    }
}
