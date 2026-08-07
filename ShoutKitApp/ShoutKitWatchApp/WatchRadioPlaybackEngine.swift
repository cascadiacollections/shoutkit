import AVFoundation
import Foundation
import Playback

@MainActor
final class WatchRadioPlaybackEngine: NSObject, RadioPlaybackEngine {
    var onStatusChange: ((AudioStatus) -> Void)?
    var onTrackInfo: ((AudioTrackInfo) -> Void)?

    private var player: AVPlayer?
    private var timeControlObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var failedToEndObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    override init() {
        super.init()
        observeAudioSessionNotifications()
    }

    isolated deinit {
        tearDownPlayer()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
    }

    // `streamGeneration` tags ICY metadata so the controller can discard track
    // callbacks from a superseded stream after a fast station switch (see
    // AudioStreamingPlaybackEngine). This engine emits no track info, so it only
    // needs to satisfy the `AudioOutput` signature.
    func start(url: URL, streamGeneration _: UInt64) {
        tearDownPlayer()

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true

        observe(player: player, item: item)

        self.player = player
        onStatusChange?(.buffering)
        activateAudioSession { [weak self] in
            guard let self, self.player === player else { return }
            player.play()
        }
    }

    func pause() {
        player?.pause()
        onStatusChange?(.paused)
    }

    func resume() {
        guard let player else { return }
        activateAudioSession { [weak self] in
            guard let self, self.player === player else { return }
            player.play()
        }
    }

    func stop() {
        player?.pause()
        tearDownPlayer()
        deactivateAudioSession()
    }

    private func observe(player: AVPlayer, item: AVPlayerItem) {
        timeControlObservation = player.observe(
            \.timeControlStatus,
            options: [.initial, .new]
        ) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player === player else { return }
                self.handleTimeControlStatus(player.timeControlStatus)
            }
        }
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player?.currentItem === item else { return }
                self.handleItemStatus(item.status, item: item)
            }
        }
        // `queue: .main` + `MainActor.assumeIsolated`, rather than `queue: nil` and
        // a `Task { @MainActor }`. This callback needs the failed `AVPlayerItem`
        // itself to compare against the current one, and neither `Notification`
        // nor `AVPlayerItem` is `Sendable` — capturing either into a task sends it
        // across an isolation boundary, which is the data race Swift 6 refuses to
        // compile (`sending 'notification' risks causing data races`).
        //
        // Main-queue delivery makes the closure body and the isolated block one
        // synchronous region, so nothing is sent anywhere. Same remedy as
        // AudioStreamingPlaybackEngine+Session's audio-session observers, and safe
        // for the same reason: `OperationQueue.main` runs its blocks on the main
        // thread, which is what `assumeIsolated` requires.
        //
        // The two audio-session observers below keep `queue: nil` + `Task`: they
        // only ever send `UInt`/`Bool`/enum values read off the notification in the
        // closure body, so they never had this problem.
        failedToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let failedItem = notification.object as? AVPlayerItem
            let reportedError = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            MainActor.assumeIsolated {
                guard let self,
                      let failedItem,
                      self.player?.currentItem === failedItem else { return }
                let message = reportedError?.localizedDescription
                    ?? failedItem.error?.localizedDescription
                    ?? "The stream stopped unexpectedly."
                self.onStatusChange?(.failed(.streamFailed(message)))
            }
        }
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .paused:
            guard player?.currentItem != nil else { return }
            onStatusChange?(.paused)
        case .waitingToPlayAtSpecifiedRate:
            onStatusChange?(.buffering)
        case .playing:
            onStatusChange?(.playing)
        @unknown default:
            break
        }
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status, item: AVPlayerItem) {
        if status == .failed {
            onStatusChange?(.failed(.streamFailed(
                item.error?.localizedDescription ?? "The stream stopped unexpectedly."
            )))
        }
    }

    private func tearDownPlayer() {
        timeControlObservation?.invalidate()
        itemStatusObservation?.invalidate()
        timeControlObservation = nil
        itemStatusObservation = nil
        if let failedToEndObserver {
            NotificationCenter.default.removeObserver(failedToEndObserver)
            self.failedToEndObserver = nil
        }
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    private func activateAudioSession(completion: @escaping @MainActor () -> Void) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        // Ordinary system alerts duck this stream instead of interrupting it, so a
        // notification can't pause the watch's audio (and leave it paused when iOS
        // omits the resume hint). Genuine interruptions still arrive normally.
        try? session.setPrefersNoInterruptionsFromSystemAlerts(true)
        session.activate(options: []) { _, _ in
            Task { @MainActor in completion() }
        }
    }

    private func observeAudioSessionNotifications() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observeInterruptions(on: session, with: center)
        observeRouteChanges(on: session, with: center)
    }

    private func observeInterruptions(on session: AVAudioSession, with center: NotificationCenter) {
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
                return
            }

            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)

            Task { @MainActor [weak self] in
                guard let self else { return }
                switch type {
                case .began:
                    self.onStatusChange?(.interruptionBegan)
                case .ended:
                    // Read on the main actor rather than captured from the
                    // notification block (`AVAudioSession` isn't `Sendable`), and
                    // read at all because the controller resumes a hintless end
                    // only when nothing else holds audio.
                    self.onStatusChange?(.interruptionEnded(
                        shouldResume: shouldResume,
                        otherAudioIsPlaying: AVAudioSession.sharedInstance().isOtherAudioPlaying
                    ))
                @unknown default:
                    break
                }
            }
        }
    }

    private func observeRouteChanges(on session: AVAudioSession, with center: NotificationCenter) {
        routeChangeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch reason {
                case .oldDeviceUnavailable:
                    guard let player = self.player, player.timeControlStatus != .paused else { return }
                    self.onStatusChange?(.routeLost)
                case .newDeviceAvailable:
                    self.onStatusChange?(.routeAvailable)
                @unknown default:
                    break
                }
            }
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
