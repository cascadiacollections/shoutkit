// Spatial audio forwarding, split out of PlaybackController.swift for the same
// 400-line `file_length` reason as PlaybackController+Recovery.swift.

extension PlaybackController {
    /// Whether the active ``AudioOutput`` can render spatial audio
    /// virtualization. `false` for engines with no supported way to insert an
    /// environment node into their render chain (`AVPlayer`-backed engines,
    /// and any ``AudioOutput`` test double that isn't also a
    /// ``RadioPlaybackEngine``) — settings UI should hide the control entirely
    /// rather than show one that does nothing.
    public var supportsSpatialAudio: Bool {
        (output as? any RadioPlaybackEngine)?.supportsSpatialAudio ?? false
    }

    /// Enables or disables spatial audio virtualization on the active output.
    /// A no-op when ``supportsSpatialAudio`` is `false`.
    public func setSpatialAudioEnabled(_ isEnabled: Bool) {
        (output as? any RadioPlaybackEngine)?.setSpatialAudioEnabled(isEnabled)
    }

    /// Applies the persisted spatial audio preference at startup.
    public func restoreSpatialAudioPreference(isEnabled: Bool) {
        setSpatialAudioEnabled(isEnabled)
    }
}
