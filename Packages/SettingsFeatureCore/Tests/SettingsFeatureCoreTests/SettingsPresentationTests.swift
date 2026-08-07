import Testing

@testable import SettingsFeatureCore

struct SettingsPresentationTests {
    @Test func preciseLocationToggleTracksFeatureFlag() {
        #expect(SettingsPresentation.shouldShowPreciseGeoLocationToggle(isGeoStationsEnabled: true))
        #expect(SettingsPresentation.shouldShowPreciseGeoLocationToggle(isGeoStationsEnabled: false) == false)
    }

    @Test func validEqualizerRawValueIsPreserved() {
        let rawValue = SettingsPresentation.resolvedEqualizerPresetRawValue(
            storedRawValue: 2,
            availablePresetRawValues: [0, 1, 2, 3],
            fallbackRawValue: 0
        )

        #expect(rawValue == 2)
    }

    @Test func invalidEqualizerRawValueFallsBack() {
        let rawValue = SettingsPresentation.resolvedEqualizerPresetRawValue(
            storedRawValue: 999,
            availablePresetRawValues: [0, 1, 2, 3],
            fallbackRawValue: 0
        )

        #expect(rawValue == 0)
    }
}
