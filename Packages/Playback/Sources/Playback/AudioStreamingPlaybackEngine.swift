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
        activateSession()
        player.play(url: url)
    }

    public func pause() {
        player.pause()
        onStatusChange?(.paused)
    }

    public func resume() {
        activateSession()
        player.resume()
    }

    public func stop() {
        sessionDeactivationTask?.cancel()
        player.stop()
        sessionDeactivationTask = Task { @MainActor in
            await self.deactivateSessionAfterStop()
        }
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
            case .ready, .running, .stopped, .error, .disposed:
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
            self.onStatusChange?(.failed(Self.classify(error)))
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
