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

    func start(url: URL) {
        configureAudioSession()
        tearDownPlayer()

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true

        observe(player: player, item: item)

        self.player = player
        onStatusChange?(.buffering)
        player.play()
    }

    func pause() {
        player?.pause()
        onStatusChange?(.paused)
    }

    func resume() {
        guard let player else { return }
        configureAudioSession()
        player.play()
    }

    func stop() {
        player?.pause()
        tearDownPlayer()
        deactivateAudioSession()
    }

    private func observe(player: AVPlayer, item: AVPlayerItem) {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                self?.handleTimeControlStatus(player.timeControlStatus)
            }
        }
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                self?.handleItemStatus(item.status, item: item)
            }
        }
        failedToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self?.onStatusChange?(.failed(.streamFailed(
                error?.localizedDescription ?? item.error?.localizedDescription ?? "The stream stopped unexpectedly."
            )))
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

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback)
        try? session.setActive(true)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
