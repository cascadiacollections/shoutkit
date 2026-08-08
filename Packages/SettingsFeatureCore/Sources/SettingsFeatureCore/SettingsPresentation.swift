public enum SettingsPresentation {
    public static func shouldShowPreciseGeoLocationToggle(isGeoStationsEnabled: Bool) -> Bool {
        isGeoStationsEnabled
    }

    public static func resolvedEqualizerPresetRawValue(
        storedRawValue: Int,
        availablePresetRawValues: [Int],
        fallbackRawValue: Int
    ) -> Int {
        availablePresetRawValues.contains(storedRawValue) ? storedRawValue : fallbackRawValue
    }
}
