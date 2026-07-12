import AVFoundation
import Foundation

/// Low-level audio status reported by an ``AudioOutput`` back to the controller.
public enum AudioStatus: Equatable, Sendable {
    case buffering
    case playing
    case paused
    case failed(String)
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

#if canImport(UIKit)

/// `AVPlayer`-backed audio output. Configures the shared audio session, observes
/// playback status, parses ICY timed metadata, and reacts to audio-session
/// interruptions and route changes. iOS-only (`AVAudioSession`); the
/// ``AudioOutput`` protocol above stays platform-agnostic so the controller and
/// its tests build on the mac host.
@MainActor
public final class AVPlayerAudioOutput: NSObject, AudioOutput {
    public var onStatusChange: ((AudioStatus) -> Void)?
    public var onTrackInfo: ((AudioTrackInfo) -> Void)?

    private var player: AVPlayer?
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var timeControlObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?

    /// Incremented on every start/teardown. Async status hops capture the value at
    /// registration time so a late delivery from a previous player is dropped
    /// instead of being attributed to the newly started station.
    private var generation = 0

    /// Incremented on every metadata push. Each push loads its string values
    /// asynchronously, so a slow load from an older push could otherwise
    /// complete *after* a newer one and regress the track info; only the
    /// latest push is allowed to deliver.
    private var metadataPushSequence = 0

    // Block-based notification observers are not auto-removed on dealloc, so
    // deinit is isolated to read this on the main actor without an escape hatch.
    private var notificationTokens: [NSObjectProtocol] = []

    override public init() {
        super.init()
        observeAudioSessionNotifications()
    }

    isolated deinit {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    public func start(url: URL) {
        teardownPlayer()
        activateSession()

        generation += 1
        let generation = self.generation

        let item = AVPlayerItem(url: url)

        let metadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        metadataOutput.setDelegate(self, queue: .main)
        item.add(metadataOutput)
        self.metadataOutput = metadataOutput

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                let failure = PlaybackFailure.classify(
                    playerError: self.player?.error,
                    itemError: self.player?.currentItem?.error ?? item.error
                )
                self.onStatusChange?(.failed(failure.message))
            }
        }

        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true

        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                switch status {
                case .waitingToPlayAtSpecifiedRate:
                    self.onStatusChange?(.buffering)
                case .playing:
                    self.onStatusChange?(.playing)
                case .paused:
                    self.onStatusChange?(.paused)
                @unknown default:
                    break
                }
            }
        }

        self.player = player
        onStatusChange?(.buffering)
        player.play()
    }

    public func pause() {
        player?.pause()
        onStatusChange?(.paused)
    }

    public func resume() {
        guard let player else { return }
        activateSession()
        player.play()
    }

    /// Full stop: tears down the player and releases the audio session so other
    /// apps may resume their audio.
    public func stop() {
        teardownPlayer()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// Tears down the current player without deactivating the audio session —
    /// station switches must not hand audio focus back to other apps mid-switch.
    private func teardownPlayer() {
        generation += 1
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        statusObservation?.invalidate()
        statusObservation = nil
        if let metadataOutput, let item = player?.currentItem {
            item.remove(metadataOutput)
        }
        metadataOutput = nil
        player?.pause()
        player = nil
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
                guard let self, self.player != nil else { return }
                self.pause()
            }
        })
    }
}

extension AVPlayerAudioOutput: AVPlayerItemMetadataOutputPushDelegate {
    public nonisolated func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: sending [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        // Delegate queue is `.main` (set in `start`), so keep AVFoundation
        // metadata objects on the main actor while loading their async values.
        MainActor.assumeIsolated {
            metadataPushSequence += 1
            let sequence = metadataPushSequence
            _ = Task { @MainActor in
                // A push can carry several rotations; the latest group wins.
                guard let streamTitle = await Self.title(in: groups) else { return }
                let trackInfo = ICYMetadataParser.parseTrack(from: streamTitle)

                // Drop late deliveries from a previous item after a station
                // switch, and out-of-order completions from an older push
                // whose value load lost the race to a newer one.
                guard output === metadataOutput, sequence == metadataPushSequence else { return }
                onTrackInfo?(trackInfo)
            }
        }
    }

    /// ICY streams carry `StreamTitle` and `StreamUrl` as separate items in the
    /// same group — prefer the explicit title, then a generic title (ID3/HLS
    /// streams), and never surface the URL item as a track name.
    private static func title(in groups: [AVTimedMetadataGroup]) async -> String? {
        for group in groups.reversed() {
            if let value = await Self.title(in: group.items) {
                return value
            }
        }
        return nil
    }

    private static func title(in items: [AVMetadataItem]) async -> String? {
        if let item = items.first(where: { $0.identifier == .icyMetadataStreamTitle }),
           let icy = try? await item.load(.stringValue),
           icy.isEmpty == false {
            return icy
        }
        if let item = items.first(where: { $0.commonKey == .commonKeyTitle }),
           let common = try? await item.load(.stringValue),
           common.isEmpty == false {
            return common
        }
        for item in items where item.identifier != .icyMetadataStreamURL {
            if let value = try? await item.load(.stringValue), value.isEmpty == false {
                return value
            }
        }
        return nil
    }
}

#endif
