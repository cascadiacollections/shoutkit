import Playback
import Testing

@testable import SettingsFeatureCore

struct SettingsPresentationTests {
    @Test(arguments: EqualizerPreset.allCases)
    func everyStoredPresetRoundTrips(preset: EqualizerPreset) {
        #expect(SettingsPresentation.resolvedEqualizerPreset(storedRawValue: preset.rawValue) == preset)
    }

    @Test(arguments: [-1, 999, Int.max])
    func unrecognisedRawValueFallsBackToFlat(rawValue: Int) {
        #expect(SettingsPresentation.resolvedEqualizerPreset(storedRawValue: rawValue) == .normal)
    }

    /// `.normal` is the fallback because it is flat, not because it is the
    /// first case — see `EqualizerPreset`'s note on asymmetric gain ranges.
    @Test func fallbackPresetHasNoCurve() {
        #expect(SettingsPresentation.resolvedEqualizerPreset(storedRawValue: 999).curve == nil)
    }
}
