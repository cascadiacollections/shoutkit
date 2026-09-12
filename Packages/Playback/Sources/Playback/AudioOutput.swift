import Foundation

/// Low-level audio status reported by an ``AudioOutput`` back to the controller.
public enum AudioStatus: Equatable, Sendable {
    case buffering
    case playing
    case paused
    case failed(PlaybackError)
    /// The stream reached the natural end of its content — a finite programme
    /// (a newscast, a recorded show) played through to its last byte.
    ///
    /// Deliberately *not* `.failed`: a live stream the server drops looks the
    /// same to a player but means something different, and conflating the two
    /// is what made a finished broadcast restart itself through the controller's
    /// auto-reconnect. So report this only when the ending is genuinely the
    /// content running out, and keep reporting `.failed` when it can't be told
    /// apart. Each engine has its own evidence for that:
    /// `AudioStreamingPlaybackEngine` compares how far it played against the
    /// entry's duration, which live audio doesn't have at all; the `AVPlayer`
    /// engines take it from `AVPlayerItemDidPlayToEndTime`, which a dropped
    /// stream never reaches — that arrives as
    /// `AVPlayerItemFailedToPlayToEndTime` instead.
    case endOfStream
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
    /// The system rebuilt its media services. Audio objects have been
    /// recreated, but playback must wait for a fresh listener action.
    case mediaServicesReset
}

/// An output observation tied to the stream request that produced it.
/// System-wide events have no generation; playback, failure, metadata-adjacent,
/// and end-of-stream events carry the generation passed to `start`.
public struct AudioStatusUpdate: Equatable, Sendable {
    public let status: AudioStatus
    public let streamGeneration: UInt64?

    public init(_ status: AudioStatus, streamGeneration: UInt64? = nil) {
        self.status = status
        self.streamGeneration = streamGeneration
    }

    public static var buffering: Self {
        Self(.buffering)
    }

    public static var playing: Self {
        Self(.playing)
    }

    public static var paused: Self {
        Self(.paused)
    }

    public static var endOfStream: Self {
        Self(.endOfStream)
    }

    public static var interruptionBegan: Self {
        Self(.interruptionBegan)
    }

    public static var routeLost: Self {
        Self(.routeLost)
    }

    public static var routeAvailable: Self {
        Self(.routeAvailable)
    }

    public static var mediaServicesReset: Self {
        Self(.mediaServicesReset)
    }

    public static func failed(_ error: PlaybackError) -> Self {
        Self(.failed(error))
    }

    public static func interruptionEnded(shouldResume: Bool, otherAudioIsPlaying: Bool) -> Self {
        Self(.interruptionEnded(shouldResume: shouldResume, otherAudioIsPlaying: otherAudioIsPlaying))
    }
}

/// A live "now playing" track update parsed from a stream's ICY metadata.
public struct AudioTrackInfo: Equatable, Sendable {
    /// The track title, or `nil` when the stream sent none.
    public let title: String?

    /// The performing artist, or `nil` when the stream sent none or the
    /// metadata could not be split into artist and title.
    public let artist: String?

    /// The value handed to ``AudioOutput/start(url:streamGeneration:)`` for the
    /// stream this update came from. See that method for why it matters.
    public let streamGeneration: UInt64

    /// Creates a track update.
    ///
    /// - Parameters:
    ///   - title: The track title, or `nil` if unknown.
    ///   - artist: The performing artist, or `nil` if unknown.
    ///   - streamGeneration: The token from
    ///     ``AudioOutput/start(url:streamGeneration:)`` for the stream this
    ///     update describes. The default of `0` exists for tests and for
    ///     single-stream callers; an engine that leaves it defaulted will have
    ///     its metadata misattributed across station changes.
    public init(title: String?, artist: String?, streamGeneration: UInt64 = 0) {
        self.title = title
        self.artist = artist
        self.streamGeneration = streamGeneration
    }
}

/// The audio playback mechanism behind ``PlaybackController`` — the seam that
/// keeps this package free of a codec dependency.
///
/// No conformance ships in `Playback`. See <doc:RegisteringAPlaybackEngine> for
/// how to supply one, and prefer conforming to ``RadioPlaybackEngine`` (which
/// refines this protocol) unless you have a reason not to: the equalizer and
/// spatial-audio capability probes are conditional casts to that protocol, so a
/// bare `AudioOutput` silently reports no support for either.
///
/// ### Implementing this protocol
///
/// Two contracts are not expressible in the signatures:
///
/// - Echo ``AudioOutput/start(url:streamGeneration:)``'s token back on every
///   ``AudioTrackInfo`` and stream-scoped ``AudioStatusUpdate`` you emit.
/// - Drive ``onStatusChange`` as the stream progresses. A controller that never
///   observes ``AudioStatus/playing`` stays in its loading state forever, which
///   looks identical to having no engine at all.
///
/// - Important: ``PlaybackController`` **takes ownership of both callbacks**.
///   Its initializer assigns ``onStatusChange`` and ``onTrackInfo``, discarding
///   anything set beforehand, and there is no mechanism for a second observer.
///   Observe playback through the controller instead.
@MainActor
public protocol AudioOutput: AnyObject {
    /// Invoked when the engine's playback status changes.
    ///
    /// Assigned by ``PlaybackController`` during initialization; see the note on
    /// callback ownership above. Called on the main actor.
    var onStatusChange: ((AudioStatusUpdate) -> Void)? { get set }

    /// Invoked when the engine decodes a new track update from stream metadata.
    ///
    /// Assigned by ``PlaybackController`` during initialization; see the note on
    /// callback ownership above. Called on the main actor.
    var onTrackInfo: ((AudioTrackInfo) -> Void)? { get set }

    /// Begins buffering and playing `url`, replacing any stream already playing.
    ///
    /// - Parameters:
    ///   - url: The stream endpoint to play.
    ///   - streamGeneration: A monotonically increasing token identifying this
    ///     playback attempt. Every track-info and stream-status callback must
    ///     carry this value back. The controller uses it to discard callbacks
    ///     that arrive after the listener has switched stations.
    func start(url: URL, streamGeneration: UInt64)

    /// Pauses playback, keeping the connection open where the transport allows it.
    ///
    /// Report ``AudioStatus/paused`` once the pause takes effect.
    func pause()

    /// Resumes playback after ``pause()``.
    ///
    /// Report ``AudioStatus/buffering`` and then ``AudioStatus/playing`` as the
    /// stream recovers. Live streams generally cannot resume from the paused
    /// position; reconnecting to the live edge is the expected behavior.
    func resume()

    /// Stops playback and releases the stream's resources.
    ///
    /// After this, ``start(url:streamGeneration:)`` must be able to begin a fresh
    /// stream on the same instance.
    func stop()
}
