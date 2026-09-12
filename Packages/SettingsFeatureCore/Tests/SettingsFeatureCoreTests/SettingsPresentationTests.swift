import Playback
@testable import SettingsFeatureCore
import Testing

struct SettingsPresentationTests {
    @Test(arguments: EqualizerPreset.allCases)
    func `every stored preset round trips`(preset: EqualizerPreset) {
        #expect(SettingsPresentation.resolvedEqualizerPreset(storedRawValue: preset.rawValue) == preset)
    }

    @Test(arguments: [-1, 999, Int.max])
    func `unrecognised raw value falls back to flat`(rawValue: Int) {
        #expect(SettingsPresentation.resolvedEqualizerPreset(storedRawValue: rawValue) == .normal)
    }

    /// `.normal` is the fallback because it is flat, not because it is the
    /// first case — see `EqualizerPreset`'s note on asymmetric gain ranges.
    @Test func `fallback preset has no curve`() {
        #expect(SettingsPresentation.resolvedEqualizerPreset(storedRawValue: 999).curve == nil)
    }
}
