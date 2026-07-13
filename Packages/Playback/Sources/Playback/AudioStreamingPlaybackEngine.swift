#if canImport(UIKit)
import AudioStreaming
import AVFoundation
import Foundation

/// ``RadioPlaybackEngine`` backed by AudioStreaming's `AudioPlayer`
/// (`AVAudioEngine`), registered as the production ``Container/radioPlaybackEngine``
/// default. AudioStreaming doesn't touch `AVAudioSession` itself, so session
/// activation/teardown and interruption/route-change handling here mirror
/// ``AVPlayerAudioOutput``.
@MainActor
public final class AudioStreamingPlaybackEngine: RadioPlaybackEngine {
    public var onStatusChange: ((AudioStatus) -> Void)?
    public var onTrackInfo: ((AudioTrackInfo) -> Void)?

    private let player = AudioPlayer()

    // Block-based notification observers are not auto-removed on dealloc, so
    // deinit is isolated to read this on the main actor without an escape hatch.
    private var notificationTokens: [NSObjectProtocol] = []

    public init() {
        player.delegate = self
        observeAudioSessionNotifications()
    }

    isolated deinit {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    public func start(url: URL) {
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
        player.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
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

    /// Maps an AudioStreaming error to the same typed failure `AVPlayerAudioOutput`
    /// surfaces, reusing its URL-error classification for the one case
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
        // Delivered via the library's own main-queue dispatch (asyncOnMain), so
        // this is always actually running on the main actor already.
        MainActor.assumeIsolated {
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
        MainActor.assumeIsolated {
            self.onStatusChange?(.failed(Self.classify(error)))
        }
    }

    public nonisolated func audioPlayerDidCancel(player: AudioPlayer, queuedItems: [AudioEntryId]) {}

    /// The one ICY metadata seam: extract `StreamTitle` and run it through the
    /// same parser `AVPlayerAudioOutput` uses, so both engines feed
    /// `PlaybackController` identically.
    public nonisolated func audioPlayerDidReadMetadata(player: AudioPlayer, metadata: [String: String]) {
        guard let streamTitle = metadata["StreamTitle"] ?? metadata["streamtitle"] else { return }
        let trackInfo = ICYMetadataParser.parseTrack(from: streamTitle)
        MainActor.assumeIsolated {
            self.onTrackInfo?(trackInfo)
        }
    }
}

#endif
