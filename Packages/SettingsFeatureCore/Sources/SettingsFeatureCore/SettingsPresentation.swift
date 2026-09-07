import Playback

/// Value-in/value-out decisions the settings surface makes, held here so they
/// can be exercised without a `SettingsStore`, a `PlaybackController`, or a
/// SwiftUI environment.
public enum SettingsPresentation {
    /// Resolves the persisted equalizer raw value to a preset.
    ///
    /// The stored value is a bare `Int` in `SettingsStore`, so it survives a
    /// preset being renumbered or removed and can name a case that no longer
    /// exists. Anything unrecognised resolves to ``EqualizerPreset/normal`` —
    /// flat — rather than to the first case, so a stale value can never leave
    /// the listener with a curve they didn't pick.
    public static func resolvedEqualizerPreset(storedRawValue: Int) -> EqualizerPreset {
        EqualizerPreset(rawValue: storedRawValue) ?? .normal
    }
}
