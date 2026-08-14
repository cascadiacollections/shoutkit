import Foundation

/// Abstraction over the streaming engine backing ``PlaybackController``'s
/// ``AudioOutput``, resolved via Factory so the concrete backend can be swapped
/// without touching call sites.
///
/// No implementation of this protocol ships in this package: the production
/// engine is `AudioStreamingPlaybackEngine` in the iOS-only
/// `PlaybackEngineAudioStreaming` package, and the watch app supplies its own
/// `AVPlayer`-backed one. That is the seam that keeps `Playback` free of a codec
/// dependency (#122).
///
/// ``supportsEqualizer``/``setEqualizerPreset(_:)`` default to "no EQ" so an
/// engine that can't insert a filter into its render chain (``StubRadioPlaybackEngine``,
/// the watch's `AVPlayer`-backed engine) doesn't have to implement anything —
/// it degrades automatically rather than exposing a control that does nothing.
@MainActor
public protocol RadioPlaybackEngine: AudioOutput {
    /// Whether this engine can apply an ``EqualizerPreset``. `AVPlayer` has no
    /// supported way to insert a filter into its render chain; only an
    /// `AVAudioEngine`-backed engine (`AudioStreamingPlaybackEngine`) can.
    var supportsEqualizer: Bool { get }

    /// Applies `preset`'s gain curve to this engine's equalizer, if any.
    /// A no-op when ``supportsEqualizer`` is `false`.
    func setEqualizerPreset(_ preset: EqualizerPreset)

    /// Whether this engine can render a head-tracked binaural virtualization
    /// of the stream over headphones. Same reasoning as ``supportsEqualizer``:
    /// only an `AVAudioEngine`-backed engine can insert the environment node
    /// this needs, and only on hardware with `CMHeadphoneMotionManager` head
    /// tracking (iOS; not watchOS).
    ///
    /// This is a stereo virtualization effect (HRTF rendering plus head
    /// tracking), not object-based spatial audio — the stream itself carries
    /// no channel/object separation for that. The name matches how Apple
    /// labels the same technique for non-Atmos content elsewhere in the OS.
    var supportsSpatialAudio: Bool { get }

    /// Enables or disables spatial audio virtualization. A no-op when
    /// ``supportsSpatialAudio`` is `false`.
    func setSpatialAudioEnabled(_ isEnabled: Bool)
}

public extension RadioPlaybackEngine {
    var supportsEqualizer: Bool { false }
    func setEqualizerPreset(_ preset: EqualizerPreset) {}

    var supportsSpatialAudio: Bool { false }
    func setSpatialAudioEnabled(_ isEnabled: Bool) {}
}

/// Placeholder ``RadioPlaybackEngine`` registered until a concrete engine lands.
/// Plays nothing — it exists so ``Container/radioPlaybackEngine`` always resolves
/// to something functional in previews and tests.
@MainActor
public final class StubRadioPlaybackEngine: RadioPlaybackEngine {
    public var onStatusChange: ((AudioStatus) -> Void)?
    public var onTrackInfo: ((AudioTrackInfo) -> Void)?

    public init() {}

    public func start(url: URL, streamGeneration: UInt64) {}
    public func pause() {}
    public func resume() {}
    public func stop() {}
}
