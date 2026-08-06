import Foundation

/// Low-level audio status reported by an ``AudioOutput`` back to the controller.
public enum AudioStatus: Equatable, Sendable {
    case buffering
    case playing
    case paused
    case failed(PlaybackError)
    /// The system interrupted playback (phone call, Siri, another app took focus).
    case interruptionBegan
    /// The interruption ended. `shouldResume` reflects the system's hint, which
    /// iOS does not always set even for interruptions that plainly should resume;
    /// `otherAudioIsPlaying` reports whether another app holds audio *now*, which
    /// is what makes resuming without the hint safe rather than a way to yank the
    /// session back from whatever the listener started meanwhile. The policy that
    /// weighs the two lives in `PlaybackController.handleInterruptionEnded`.
    case interruptionEnded(shouldResume: Bool, otherAudioIsPlaying: Bool)
    /// The active audio route disappeared, such as unplugged headphones.
    case routeLost
    /// A new audio route became available.
    case routeAvailable
}

/// A live "now playing" track update parsed from a stream's ICY metadata.
public struct AudioTrackInfo: Equatable, Sendable {
    public let title: String?
    public let artist: String?
    public let streamGeneration: UInt64

    public init(title: String?, artist: String?, streamGeneration: UInt64 = 0) {
        self.title = title
        self.artist = artist
        self.streamGeneration = streamGeneration
    }
}

/// Abstraction over the actual audio playback mechanism so ``PlaybackController``
/// can be exercised in tests with a fake implementation.
@MainActor
public protocol AudioOutput: AnyObject {
    var onStatusChange: ((AudioStatus) -> Void)? { get set }
    var onTrackInfo: ((AudioTrackInfo) -> Void)? { get set }

    func start(url: URL, streamGeneration: UInt64)
    func pause()
    func resume()
    func stop()
}
