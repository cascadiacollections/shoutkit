import AudioStreaming
import AVFoundation
import Foundation
import os
import Playback

/// `RadioPlaybackEngine` backed by AudioStreaming's `AudioPlayer`
/// (`AVAudioEngine`), registered over the `Container.radioPlaybackEngine` stub
/// default by `registerProductionPlaybackEngine()`.
///
/// AudioStreaming doesn't touch `AVAudioSession` itself, so this type owns
/// the session outright; everything session-shaped (configuration, activation,
/// teardown, and the OS-disruption notifications) lives one file over, in
/// AudioStreamingPlaybackEngine+Session.swift. Members that file drives are
/// `internal` rather than `private` for that reason; none of it is public API.
@MainActor
public final class AudioStreamingPlaybackEngine: RadioPlaybackEngine {
    static let logger = Logger(subsystem: "ShoutKit.Playback", category: "AudioStreamingPlaybackEngine")

    public var onStatusChange: ((AudioStatus) -> Void)?
    public var onTrackInfo: ((AudioTrackInfo) -> Void)?

    /// `var`, not `let`: a media-services reset invalidates every audio object in
    /// the process (including the `AVAudioEngine` inside this player), so
    /// recovering means building a new one — see `handleMediaServicesReset()`.
    var player = AudioPlayer()
    private let streamGeneration = OSAllocatedUnfairLock(initialState: UInt64.zero)
    var sessionDeactivationTask: Task<Void, Never>?
    var sessionActivationTask: Task<Void, Never>?

    /// The URL of the stream currently loaded into `player`, kept so ``resume()``
    /// can rejoin a stream the player is no longer able to resume.
    var currentURL: URL?

    /// Whether the most recent `.stopped` transition was one we asked for.
    /// AudioStreaming reports `.stopped` both for ``stop()`` and for its
    /// end-of-stream path, which a live stream reaches whenever the server drops
    /// the connection — only the latter is a failure.
    var didRequestStop = false

    /// One failure report per stream. A single collapse can surface as both an
    /// `AudioPlayerError` and a `.stopped` transition, and each report the
    /// controller sees spends another of its bounded reconnect attempts.
    private var hasReportedFailure = false

    // Block-based notification observers are not auto-removed on dealloc, so
    // deinit is isolated to read this on the main actor without an escape hatch.
    var notificationTokens: [NSObjectProtocol] = []

    /// The attached `AVAudioUnitEQ`, if a preset has been applied — see
    /// AudioStreamingPlaybackEngine+Equalizer.swift. `nil` until the first
    /// `setEqualizerPreset(_:)` call, and again immediately after a
    /// media-services reset until it's rebuilt.
    var equalizerNode: AVAudioUnitEQ?

    /// The last preset applied, kept so `handleMediaServicesReset()` can
    /// re-attach and re-apply it to the rebuilt engine.
    var currentEqualizerPreset: EqualizerPreset = .normal

    public init() {
        player.delegate = self
        configureSession()
        observeAudioSessionNotifications()
    }

    isolated deinit {
        sessionDeactivationTask?.cancel()
        sessionActivationTask?.cancel()
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    public func start(url: URL, streamGeneration: UInt64) {
        self.streamGeneration.withLock { $0 = streamGeneration }
        currentURL = url
        didRequestStop = false
        hasReportedFailure = false
        withActiveSession { [weak self] in
            // A newer start (or a stop) supersedes this one; the pending
            // activation is cancelled for those, and this is the belt to that
            // brace — never begin streaming a URL that is no longer current.
            guard let self, self.currentURL == url else { return }
            self.player.play(url: url)
        }
    }

    public func pause() {
        // A pause outranks a deferred activation: without this, a resume the
        // session refused could still start audio moments after the listener —
        // or the system, mid-interruption — asked for silence.
        cancelPendingSessionActivation()
        player.pause()
        onStatusChange?(.paused)
    }

    public func resume() {
        withActiveSession { [weak self] in
            guard let self else { return }
            // `AudioPlayer.resume()` acts only when AudioStreaming's own state is
            // exactly `.paused`, and that state can differ from ours: the system
            // stops the engine for an interruption without telling the library, and
            // a live stream the server closed leaves it `.stopped`. In those cases
            // `resume()` returns having done nothing — no audio, no state change —
            // so playback stayed stuck until the listener picked another station.
            // Rejoin the stream instead; live radio has no position to preserve.
            guard self.player.state == .paused else {
                self.replayCurrentStream()
                return
            }
            self.player.resume()
        }
    }

    public func stop() {
        didRequestStop = true
        cancelPendingSessionActivation()
        sessionDeactivationTask?.cancel()
        player.stop()
        sessionDeactivationTask = Task { @MainActor in
            await self.deactivateSessionAfterStop()
        }
    }

    /// Restarts the current stream from scratch — what a station switch does,
    /// minus the switch. Used when the player can't be resumed.
    private func replayCurrentStream() {
        guard let currentURL else { return }
        didRequestStop = false
        hasReportedFailure = false
        // `play(url:)` doesn't always change the player's public state (it is
        // already `.bufferring` when a stalled stream is rejoined), so the
        // transition out of paused has to be reported here or the controller
        // would keep waiting for a callback that never comes.
        onStatusChange?(.buffering)
        player.play(url: currentURL)
    }

    /// AudioStreaming's end-of-stream path stops the player without raising an
    /// error, which for live radio means the server closed the connection.
    /// Swallowing it left the controller showing a dead stream as playing — and,
    /// once paused, holding a player that would never resume. Surface it as a
    /// retryable failure so the bounded auto-reconnect takes over.
    private func handleUnexpectedStop() {
        guard didRequestStop == false else { return }
        // State changes are delivered asynchronously on the main queue, so the
        // `.stopped` from a teardown that has since been followed by a fresh
        // `start()` can land late. Ignore it unless the player is still stopped.
        guard player.state == .stopped else { return }
        // A stop the player took because of an error is reported through
        // `audioPlayerUnexpectedError` with a classified reason; let that one
        // through rather than pre-empting it with a generic message.
        guard player.stopReason != .error else { return }
        reportFailure(.streamFailed("The stream ended unexpectedly."))
    }

    func reportFailure(_ error: PlaybackError) {
        guard hasReportedFailure == false else { return }
        hasReportedFailure = true
        onStatusChange?(.failed(error))
    }

    /// Hops to the main actor, then drops the callback unless `player` is still
    /// the current one. A player discarded by `handleMediaServicesReset()` can
    /// still be finishing its own teardown, and a dead engine must not drive
    /// playback state. Compared by `ObjectIdentifier` because that is `Sendable`
    /// and this crosses isolation domains.
    private nonisolated func executeOnMainActor(
        for player: AudioPlayer,
        _ body: @escaping @MainActor () -> Void
    ) {
        let sender = ObjectIdentifier(player)
        executeOnMainActor { [weak self] in
            guard let self, ObjectIdentifier(self.player) == sender else { return }
            body()
        }
    }

    private nonisolated func executeOnMainActor(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                body()
            }
            return
        }

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                body()
            }
        }
    }

    /// Maps an AudioStreaming error to the app's typed `PlaybackError`. Unwraps
    /// the one case (`.networkError(.failure)`) that carries a real `NSError`
    /// first, since that is the only shape `PlaybackError.classifying` can read a
    /// `URLError` code out of; everything else is classified on its
    /// `localizedDescription`.
    private static func classify(_ error: AudioPlayerError) -> PlaybackError {
        let candidate: any Error
        if case let .networkError(.failure(underlying)) = error {
            candidate = underlying
        } else {
            candidate = error
        }
        return PlaybackError.classifying(candidate)
    }
}

extension AudioStreamingPlaybackEngine: AudioPlayerDelegate {
    public nonisolated func audioPlayerDidStartPlaying(player: AudioPlayer, with entryId: AudioEntryId) {}

    public nonisolated func audioPlayerDidFinishBuffering(player: AudioPlayer, with entryId: AudioEntryId) {}

    public nonisolated func audioPlayerStateChanged(
        player: AudioPlayer,
        with newState: AudioPlayerState,
        previous: AudioPlayerState
    ) {
        executeOnMainActor(for: player) {
            switch newState {
            case .playing:
                self.onStatusChange?(.playing)
            case .bufferring:
                self.onStatusChange?(.buffering)
            case .paused:
                self.onStatusChange?(.paused)
            case .stopped:
                self.handleUnexpectedStop()
            case .ready, .running, .error, .disposed:
                // `.error` arrives alongside `audioPlayerUnexpectedError`, which
                // is where the typed failure comes from; the rest are lifecycle
                // states with no equivalent in `AudioStatus`.
                break
            }
        }
    }

    public nonisolated func audioPlayerDidFinishPlaying(
        player: AudioPlayer,
        entryId: AudioEntryId,
        stopReason: AudioPlayerStopReason,
        progress: Double,
        duration: Double
    ) {}

    public nonisolated func audioPlayerUnexpectedError(player: AudioPlayer, error: AudioPlayerError) {
        executeOnMainActor(for: player) {
            self.reportFailure(Self.classify(error))
        }
    }

    public nonisolated func audioPlayerDidCancel(player: AudioPlayer, queuedItems: [AudioEntryId]) {}

    /// The one ICY metadata seam: extract `StreamTitle` and run it through
    /// `ICYMetadataParser`, so `PlaybackController` receives track info in the
    /// same shape its tests exercise.
    public nonisolated func audioPlayerDidReadMetadata(player: AudioPlayer, metadata: [String: String]) {
        // ICY key casing varies by server ("StreamTitle", "streamtitle",
        // "Streamtitle", …); try the common spellings directly, then fall back
        // to a case-insensitive scan so a noncanonical server doesn't leave
        // the previous track's title on screen indefinitely.
        let streamTitle = metadata["StreamTitle"]
            ?? metadata["streamtitle"]
            ?? metadata.first(where: { $0.key.lowercased() == "streamtitle" })?.value
        guard let streamTitle else { return }
        let generation = streamGeneration.withLock { $0 }
        let parsed = ICYMetadataParser.parseTrack(from: streamTitle)
        let trackInfo = AudioTrackInfo(title: parsed.title, artist: parsed.artist, streamGeneration: generation)
        executeOnMainActor(for: player) {
            self.onTrackInfo?(trackInfo)
        }
    }
}
