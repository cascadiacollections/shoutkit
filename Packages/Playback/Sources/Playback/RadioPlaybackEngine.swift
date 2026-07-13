import Foundation

/// Abstraction over the streaming engine backing ``PlaybackController``'s
/// ``AudioOutput``, resolved via Factory so the concrete backend can be swapped
/// (AVPlayer today, an AudioStreaming-backed engine in a future phase) without
/// touching call sites.
@MainActor
public protocol RadioPlaybackEngine: AudioOutput {}

/// Placeholder ``RadioPlaybackEngine`` registered until a concrete engine lands.
/// Plays nothing — it exists so ``Container/radioPlaybackEngine`` always resolves
/// to something functional in previews and tests.
@MainActor
public final class StubRadioPlaybackEngine: RadioPlaybackEngine {
    public var onStatusChange: ((AudioStatus) -> Void)?
    public var onTrackInfo: ((AudioTrackInfo) -> Void)?

    public init() {}

    public func start(url: URL) {}
    public func pause() {}
    public func resume() {}
    public func stop() {}
}
