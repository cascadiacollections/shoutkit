#if canImport(UIKit) && !os(watchOS)
import AudioStreaming
import AVFoundation
import Foundation
import os

/// ``RadioPlaybackEngine`` backed by AudioStreaming's `AudioPlayer`
/// (`AVAudioEngine`), registered as the production ``Container/radioPlaybackEngine``
/// default. AudioStreaming doesn't touch `AVAudioSession` itself, so session
/// activation/teardown and interruption/route-change handling live here.
@MainActor
public final class AudioStreamingPlaybackEngine: RadioPlaybackEngine {
    private static let logger = Logger(subsystem: "ShoutKit.Playback", category: "AudioStreamingPlaybackEngine")
    private static let sessionDeactivationRetryDelay: Duration = .milliseconds(150)

    public var onStatusChange: ((AudioStatus) -> Void)?
    public var onTrackInfo: ((AudioTrackInfo) -> Void)?

    private let player = AudioPlayer()
    private let streamGeneration = OSAllocatedUnfairLock(initialState: UInt64.zero)
    private var sessionDeactivationTask: Task<Void, Never>?

    /// The URL of the stream currently loaded into `player`, kept so ``resume()``
    /// can rejoin a stream the player is no longer able to resume.
    private var currentURL: URL?

    /// Whether the most recent `.stopped` transition was one we asked for.
    /// AudioStreaming reports `.stopped` both for ``stop()`` and for its
    /// end-of-stream path, which a live stream reaches whenever the server drops
    /// the connection — only the latter is a failure.
    private var didRequestStop = false

    /// One failure report per stream. A single collapse can surface as both an
    /// `AudioPlayerError` and a `.stopped` transition, and each report the
    /// controller sees spends another of its bounded reconnect attempts.
    private var hasReportedFailure = false

    // Block-based notification observers are not auto-removed on dealloc, so
    // deinit is isolated to read this on the main actor without an escape hatch.
    private var notificationTokens: [NSObjectProtocol] = []

    public init() {
        player.delegate = self
        observeAudioSessionNotifications()
    }

    isolated deinit {
        sessionDeactivationTask?.cancel()
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    public func start(url: URL, streamGeneration: UInt64) {
        self.streamGeneration.withLock { $0 = streamGeneration }
        currentURL = url
        didRequestStop = false
        hasReportedFailure = false
        activateSession()
        player.play(url: url)
    }

    public func pause() {
        player.pause()
        onStatusChange?(.paused)
    }

    public func resume() {
        activateSession()
        // `AudioPlayer.resume()` acts only when AudioStreaming's own state is
        // exactly `.paused`, and that state can differ from ours: the system
        // stops the engine for an interruption without telling the library, and
        // a live stream the server closed leaves it `.stopped`. In those cases
        // `resume()` returns having done nothing — no audio, no state change —
        // so playback stayed stuck until the listener picked another station.
        // Rejoin the stream instead; live radio has no position to preserve.
        guard player.state == .paused else {
            replayCurrentStream()
            return
        }
        player.resume()
    }

    public func stop() {
        didRequestStop = true
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

    private func reportFailure(_ error: PlaybackError) {
        guard hasReportedFailure == false else { return }
        hasReportedFailure = true
        onStatusChange?(.failed(error))
    }

    private func activateSession() {
        sessionDeactivationTask?.cancel()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func deactivateSessionAfterStop() async {
        let session = AVAudioSession.sharedInstance()

        for attempt in 0..<5 {
            guard Task.isCancelled == false else { return }
            do {
                try session.setActive(false, options: [.notifyOthersOnDeactivation])
                return
            } catch {
                guard Self.shouldRetrySessionDeactivation(error), attempt < 4 else {
                    Self.logger.error(
                        "Audio session deactivation failed after stop: \(String(describing: error), privacy: .public)"
                    )
                    return
                }
                try? await Task.sleep(for: Self.sessionDeactivationRetryDelay)
            }
        }
    }

    private static func shouldRetrySessionDeactivation(_ error: any Error) -> Bool {
        let nsError = error as NSError
        guard let code = AVAudioSession.ErrorCode(rawValue: nsError.code) else {
            return false
        }
        return code == .isBusy
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

    private func observeAudioSessionNotifications() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        // Observers use queue: .main so MainActor.assumeIsolated is safe inside.
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
                return
            }

            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)

            MainActor.assumeIsolated {
                guard let self else { return }
                switch type {
                case .began:
                    self.onStatusChange?(.interruptionBegan)
                case .ended:
                    self.onStatusChange?(.interruptionEnded(shouldResume: shouldResume))
                @unknown default:
                    break
                }
            }
        })

        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason),
                  reason == .oldDeviceUnavailable else {
                return
            }

            MainActor.assumeIsolated {
                // Headphones unplugged: pause rather than continue on the speaker.
                guard let self else { return }
                self.pause()
            }
        })
    }

    /// Maps an AudioStreaming error to the app's typed `PlaybackError`, reusing
    /// `PlaybackFailure`'s URL-error classification for the one case
    /// (`.networkError(.failure)`) that wraps a real `NSError`.
    private static func classify(_ error: AudioPlayerError) -> PlaybackError {
        let candidate: any Error
        if case let .networkError(.failure(underlying)) = error {
            candidate = underlying
        } else {
            candidate = error
        }
        switch PlaybackFailure.classify(playerError: candidate, itemError: nil) {
        case .noInternet:
            return .noInternet
        case let .stationNotAvailable(errorCode: code):
            return .stationNotAvailable(errorCode: code)
        case let .playback(message):
            return .streamFailed(message)
        }
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
        executeOnMainActor {
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
        executeOnMainActor {
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
        executeOnMainActor {
            self.onTrackInfo?(trackInfo)
        }
    }
}

#endif
