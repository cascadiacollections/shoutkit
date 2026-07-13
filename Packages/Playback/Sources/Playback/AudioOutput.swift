import Foundation

/// Low-level audio status reported by an ``AudioOutput`` back to the controller.
public enum AudioStatus: Equatable, Sendable {
    case buffering
    case playing
    case paused
    case failed(PlaybackError)
    /// The system interrupted playback (phone call, Siri, another app took focus).
    case interruptionBegan
    /// The interruption ended; `shouldResume` reflects the system's hint.
    case interruptionEnded(shouldResume: Bool)
}

/// A live "now playing" track update parsed from a stream's ICY metadata.
public struct AudioTrackInfo: Equatable, Sendable {
    public let title: String?
    public let artist: String?

    public init(title: String?, artist: String?) {
        self.title = title
        self.artist = artist
    }
}

/// Abstraction over the actual audio playback mechanism so ``PlaybackController``
/// can be exercised in tests with a fake implementation.
@MainActor
public protocol AudioOutput: AnyObject {
    var onStatusChange: ((AudioStatus) -> Void)? { get set }
    var onTrackInfo: ((AudioTrackInfo) -> Void)? { get set }

    func start(url: URL)
    func pause()
    func resume()
    func stop()
}
