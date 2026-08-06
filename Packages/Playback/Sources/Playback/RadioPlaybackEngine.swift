import Foundation

/// Abstraction over the streaming engine backing ``PlaybackController``'s
/// ``AudioOutput``, resolved via Factory so the concrete backend can be swapped
/// (AVPlayer today, an AudioStreaming-backed engine in a future phase) without
/// touching call sites.
///
/// ``supportsEqualizer``/``setEqualizerPreset(_:)`` default to "no EQ" so an
/// engine that can't insert a filter into its render chain (``StubRadioPlaybackEngine``,
/// the watch's `AVPlayer`-backed engine) doesn't have to implement anything —
/// it degrades automatically rather than exposing a control that does nothing.
@MainActor
public protocol RadioPlaybackEngine: AudioOutput {
    /// Whether this engine can apply an ``EqualizerPreset``. `AVPlayer` has no
    /// supported way to insert a filter into its render chain; only an
    /// `AVAudioEngine`-backed engine (``AudioStreamingPlaybackEngine``) can.
    var supportsEqualizer: Bool { get }

    /// Applies `preset`'s gain curve to this engine's equalizer, if any.
    /// A no-op when ``supportsEqualizer`` is `false`.
    func setEqualizerPreset(_ preset: EqualizerPreset)
}

public extension RadioPlaybackEngine {
    var supportsEqualizer: Bool { false }
    func setEqualizerPreset(_ preset: EqualizerPreset) {}
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
