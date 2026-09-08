import Foundation
#if canImport(MediaPlayer)
import MediaPlayer
#endif
import Playback
import RadioDirectory

@MainActor
final class WatchNoopNowPlayingCenter: NowPlayingPresenting {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onToggle: (() -> Void)?

#if canImport(MediaPlayer)
    private var commandTargets: [(MPRemoteCommand, Any)] = []
#endif

    init() {
        configureRemoteCommands()
    }

    isolated deinit {
#if canImport(MediaPlayer)
        for (command, target) in commandTargets {
            command.removeTarget(target)
        }
#endif
    }

    func update(station: Station, track: NowPlayingMetadata?, isPlaying: Bool, artwork: NowPlayingArtwork) {
#if canImport(MediaPlayer)
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = track?.title ?? station.name
        info[MPMediaItemPropertyArtist] = track?.artist ?? station.name
        info[MPMediaItemPropertyAlbumTitle] = station.genre
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
#endif
    }

    func clear() {
#if canImport(MediaPlayer)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
#endif
    }

    private func configureRemoteCommands() {
#if canImport(MediaPlayer)
        let center = MPRemoteCommandCenter.shared()
        var targets: [(MPRemoteCommand, Any)] = []
        targets.append((center.playCommand, center.playCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.onPlay?() }
            return .success
        }))
        targets.append((center.pauseCommand, center.pauseCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.onPause?() }
            return .success
        }))
        targets.append((center.stopCommand, center.stopCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.onStop?() }
            return .success
        }))
        targets.append((
            center.togglePlayPauseCommand,
            center.togglePlayPauseCommand.addTarget { @Sendable [weak self] _ in
                Task { @MainActor in self?.onToggle?() }
                return .success
            }
        ))
        commandTargets = targets
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.stopCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
#endif
    }
}
