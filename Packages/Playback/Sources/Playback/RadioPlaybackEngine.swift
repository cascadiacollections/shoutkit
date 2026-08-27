import Foundation
import os

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
///
/// - Important: If you are hearing silence and playback appears stuck loading,
///   this type is the first thing to check. Reaching ``start(url:streamGeneration:)``
///   on the stub means no production engine was registered — see
///   <doc:RegisteringAPlaybackEngine>. The stub logs a fault to the
///   `ShoutKit.Playback` subsystem the first time that happens, rather than
///   trapping: the watch app legitimately replaces the engine by injecting its
///   own through `PlaybackController.init(output:)`, and previews and tests want
///   a no-op engine.
@MainActor
public final class StubRadioPlaybackEngine: RadioPlaybackEngine {
    private static let logger = Logger(subsystem: "ShoutKit.Playback", category: "StubEngine")

    /// Logged at most once per process. A stuck stream will call `start` on every
    /// retry, and a fault per retry buries the first one.
    private var hasLoggedNoEngineFault = false

    public var onStatusChange: ((AudioStatus) -> Void)?
    public var onTrackInfo: ((AudioTrackInfo) -> Void)?

    public init() {}

    public func start(url: URL, streamGeneration: UInt64) {
        guard !hasLoggedNoEngineFault else { return }
        hasLoggedNoEngineFault = true
        Self.logger.fault(
            """
            StubRadioPlaybackEngine.start called — no production playback engine is registered, \
            so this stream will never produce audio and playback will stay in .loading. \
            Call registerProductionPlaybackEngine() (PlaybackEngineAudioStreaming) during \
            startup, or inject an engine via PlaybackController.init(output:).
            """
        )
    }

    public func pause() {}
    public func resume() {}
    public func stop() {}
}
