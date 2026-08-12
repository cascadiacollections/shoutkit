import Foundation
import MediaPlayer
import Playback
import RadioDirectory
import UIKit

/// tvOS ``NowPlayingPresenting``: the system Now Playing surface reached by pressing
/// the TV button, plus the Siri Remote's transport commands.
///
/// Unlike `WatchNoopNowPlayingCenter` this is a *real* implementation — tvOS shows
/// artwork, so the station favicon is fetched and attached. It stays a separate type
/// from `Playback`'s `NowPlayingCenter` rather than reusing it: that one is
/// `os(iOS)`-gated because it carries the lock-screen and Control Center contract
/// plus a Bluetooth/AVRCP artwork-resizing path that has no meaning on a TV.
/// ``NowPlayingPresenting`` is the seam, and this is the tvOS implementation of it.
///
/// Artwork is decoded with `UIImage(data:)` rather than through
/// `ImageIODownsample`. The MVP links exactly the three packages the watch app does,
/// and on a TV the decoded bitmap is both wanted at a large size and not competing
/// for memory on a backgrounded phone. If this target later links
/// `ImageIODownsample`, prefer its downsampling decode for consistency.
@MainActor
final class TVNowPlayingCenter: NowPlayingPresenting {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onToggle: (() -> Void)?

    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var artworkTask: Task<Void, Never>?
    private var artworkCacheURL: URL?
    private var cachedArtwork: MPMediaItemArtwork?
    /// The station `artworkCacheURL` belongs to, so a `.resolving` push can only
    /// hold artwork that is actually this station's.
    private var presentedStationID: String?

    init() {
        configureRemoteCommands()
    }

    isolated deinit {
        for (command, target) in commandTargets {
            command.removeTarget(target)
        }
    }

    func update(station: Station, track: NowPlayingMetadata?, isPlaying: Bool, artwork: NowPlayingArtwork) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = track?.title ?? station.name
        info[MPMediaItemPropertyArtist] = track?.artist ?? station.name
        info[MPMediaItemPropertyAlbumTitle] = station.genre
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        let targetArtworkURL = resolvedArtworkURL(for: station, artwork: artwork)
        presentedStationID = station.id

        // Only attach cached artwork if it belongs to the current target URL —
        // otherwise the previous station's art shows under the new station's name.
        if let cachedArtwork, artworkCacheURL == targetArtworkURL {
            info[MPMediaItemPropertyArtwork] = cachedArtwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtworkIfNeeded(from: targetArtworkURL)
    }

    func clear() {
        artworkTask?.cancel()
        artworkTask = nil
        artworkCacheURL = nil
        cachedArtwork = nil
        presentedStationID = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Prefers the track's artwork once resolved and falls back to the station's own.
    /// A `.resolving` push holds whatever this station already shows rather than
    /// flashing back to the station favicon for the length of a lookup.
    private func resolvedArtworkURL(for station: Station, artwork: NowPlayingArtwork) -> URL? {
        switch artwork {
        case let .resolved(url):
            return url ?? station.artworkURL
        case .resolving:
            let held = presentedStationID == station.id ? artworkCacheURL : nil
            return held ?? station.artworkURL
        }
    }

    private func loadArtworkIfNeeded(from url: URL?) {
        guard let url, url != artworkCacheURL else { return }
        artworkCacheURL = url
        // The old station's artwork must not survive a station switch.
        cachedArtwork = nil
        artworkTask?.cancel()

        artworkTask = Task { [weak self] in
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadRevalidatingCacheData
            guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                // Forget the failed URL so the next update retries it — a transient
                // error at play start must not leave the surface artless for the
                // whole session.
                self?.resetArtworkCache(ifStill: url)
                return
            }

            // Decode off the main actor: `UIImage(data:)` on a large TV-sized image
            // can hitch the focus engine and Now Playing updates.
            guard let image = await Task.detached(priority: .utility, operation: {
                UIImage(data: data)
            }).value else {
                self?.resetArtworkCache(ifStill: url)
                return
            }

            let artwork = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
            guard let self, Task.isCancelled == false else { return }
            self.cachedArtwork = artwork
            self.attachArtwork(artwork)
        }
    }

    private func attachArtwork(_ artwork: MPMediaItemArtwork) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Clears the cache marker after a failed load, but only if a newer load hasn't
    /// already claimed it for a different URL — and never for a cancelled load,
    /// whose replacement owns the marker now.
    private func resetArtworkCache(ifStill url: URL) {
        guard Task.isCancelled == false, artworkCacheURL == url else { return }
        artworkCacheURL = nil
    }

    // MediaRemote may invoke these handlers on an arbitrary queue, so they must be
    // @Sendable (non-isolated) and hop to the main actor to touch the callbacks —
    // an inherited-@MainActor closure called off-main traps under Swift 6.
    private func configureRemoteCommands() {
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
        // Live radio has no scrub position; leaving this enabled offers the remote a
        // control that can only fail.
        center.changePlaybackPositionCommand.isEnabled = false
    }
}
