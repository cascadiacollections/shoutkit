import Foundation
import ImageIO
import MediaPlayer
import os
import RadioDirectory

/// Abstraction over the system now-playing surface (lock screen / Control Center /
/// CarPlay) so ``PlaybackController`` can be tested with a spy instead of mutating
/// `MPRemoteCommandCenter.shared()` in unit tests — and so the lock-screen contract
/// (what gets pushed, when) is assertable.
@MainActor
public protocol NowPlayingPresenting: AnyObject {
    /// Remote-command callbacks (lock screen / Control Center transport buttons).
    var onPlay: (() -> Void)? { get set }
    var onPause: (() -> Void)? { get set }
    var onStop: (() -> Void)? { get set }
    var onToggle: (() -> Void)? { get set }

    /// Pushes current station + live track metadata to the system surface.
    ///
    /// - Parameters:
    ///   - station:    The currently playing station.
    ///   - track:      Live ICY track metadata, if available.
    ///   - isPlaying:  Whether playback is active.
    ///   - artworkURL: Optional album art URL to display in preference to the
    ///                 station's own artwork. Pass `nil` to fall back to the
    ///                 station URL.
    func update(station: Station, track: NowPlayingMetadata?, isPlaying: Bool, artworkURL: URL?)

    /// Removes the now-playing item from the system surface.
    func clear()
}

#if canImport(UIKit)

/// Bridges playback to the system Now Playing info center and remote command center
/// (lock screen + Control Center). Commands are forwarded to the supplied closures.
/// iOS-only (`UIImage` artwork loading); ``NowPlayingPresenting`` above stays
/// platform-agnostic so the controller and its tests build on the mac host.
@MainActor
public final class NowPlayingCenter: NowPlayingPresenting {
    public var onPlay: (() -> Void)?
    public var onPause: (() -> Void)?
    public var onStop: (() -> Void)?
    public var onToggle: (() -> Void)?

    private var artworkTask: Task<Void, Never>?
    private var artworkCacheURL: URL?
    private var cachedArtwork: MPMediaItemArtwork?

    /// Whether a station is currently active. Written on the main actor, read from
    /// MediaRemote's queue by the command handlers, hence the lock.
    private let hasActiveItem = OSAllocatedUnfairLock(initialState: false)

    // Command targets are registered per instance and must be removed on deinit
    // (a leaked target would keep receiving lock-screen commands), so deinit is
    // isolated to read this on the main actor without an escape hatch.
    private var commandTargets: [(MPRemoteCommand, Any)] = []

    public init() {
        configureRemoteCommands()
    }

    isolated deinit {
        for (command, target) in commandTargets {
            command.removeTarget(target)
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        let hasActiveItem = self.hasActiveItem

        // MediaRemote may invoke these handlers on an arbitrary queue, so they must
        // be @Sendable (non-isolated) and hop to the main actor to touch the
        // callbacks — an inherited-@MainActor closure called off-main traps under
        // Swift 6.
        var targets: [(MPRemoteCommand, Any)] = []

        targets.append((center.playCommand, center.playCommand.addTarget { @Sendable [weak self] _ in
            guard hasActiveItem.withLock({ $0 }) else { return .noActionableNowPlayingItem }
            Task { @MainActor in self?.onPlay?() }
            return .success
        }))
        targets.append((center.pauseCommand, center.pauseCommand.addTarget { @Sendable [weak self] _ in
            guard hasActiveItem.withLock({ $0 }) else { return .noActionableNowPlayingItem }
            Task { @MainActor in self?.onPause?() }
            return .success
        }))
        targets.append((center.stopCommand, center.stopCommand.addTarget { @Sendable [weak self] _ in
            guard hasActiveItem.withLock({ $0 }) else { return .noActionableNowPlayingItem }
            Task { @MainActor in self?.onStop?() }
            return .success
        }))
        let toggleCommand = center.togglePlayPauseCommand
        targets.append((toggleCommand, toggleCommand.addTarget { @Sendable [weak self] _ in
            guard hasActiveItem.withLock({ $0 }) else { return .noActionableNowPlayingItem }
            Task { @MainActor in self?.onToggle?() }
            return .success
        }))

        commandTargets = targets

        center.stopCommand.isEnabled = true
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
    }

    /// Pushes current station + live track metadata to the system.
    public func update(station: Station, track: NowPlayingMetadata?, isPlaying: Bool, artworkURL: URL?) {
        hasActiveItem.withLock { $0 = true }

        var info: [String: Any] = [:]

        let trackTitle = track?.title
        info[MPMediaItemPropertyTitle] = trackTitle ?? station.name
        info[MPMediaItemPropertyArtist] = track?.artist ?? station.name
        info[MPMediaItemPropertyAlbumTitle] = station.genre
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        // Prefer album art URL when provided; fall back to the station's own artwork.
        let targetArtworkURL = artworkURL ?? station.artworkURL

        // Only attach cached artwork if it belongs to the current target URL —
        // otherwise the previous station's art would show on the lock screen.
        if let cachedArtwork, artworkCacheURL == targetArtworkURL {
            info[MPMediaItemPropertyArtwork] = cachedArtwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtworkIfNeeded(from: targetArtworkURL)
    }

    public func clear() {
        hasActiveItem.withLock { $0 = false }
        artworkTask?.cancel()
        artworkTask = nil
        artworkCacheURL = nil
        cachedArtwork = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func loadArtworkIfNeeded(from url: URL?) {
        guard let url else { return }
        guard url != artworkCacheURL else { return }
        artworkCacheURL = url
        // The old station's artwork must not survive a station switch.
        cachedArtwork = nil
        artworkTask?.cancel()

        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url) else {
                // Forget the failed URL so the next update retries it — a
                // transient network error at play start must not leave the
                // lock screen artless for the whole session.
                self?.resetArtworkCache(ifStill: url)
                return
            }

            // Decode off the main actor — with `ShouldCacheImmediately` the
            // downsample decode is the expensive step, not `UIImage(data:)`.
            guard let image = await Task.detached(priority: .utility, operation: {
                NowPlayingCenter.decodedArtwork(from: data)
            }).value else {
                return
            }

            // MediaPlayer invokes this request handler on an arbitrary background
            // queue, so it must be @Sendable / non-isolated — capturing main-actor
            // context here traps under Swift 6 runtime isolation checks.
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
            guard let self, Task.isCancelled == false else { return }
            self.cachedArtwork = artwork

            if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
                info[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }

    /// Clears the artwork cache marker after a failed download, but only if a
    /// newer load hasn't already claimed it for a different URL — and never
    /// for a cancelled load, whose replacement owns the marker now.
    private func resetArtworkCache(ifStill url: URL) {
        guard Task.isCancelled == false, artworkCacheURL == url else { return }
        artworkCacheURL = nil
    }

    /// Downsample-decodes lock-screen artwork via ImageIO instead of
    /// `UIImage(data:)`. The decoded bitmap lives in `cachedArtwork` for the
    /// whole listening session — usually backgrounded, exactly when the
    /// system reclaims memory — so an oversized station favicon must not pin
    /// a native-resolution decode. 768 px comfortably covers the lock-screen
    /// tile; typical 600 px album art passes through untouched.
    ///
    /// A private copy of DesignSystem's downsampler: Playback deliberately
    /// doesn't depend on DesignSystem (see DECISIONS.md on `AlbumArtLookup`).
    private nonisolated static func decodedArtwork(from data: Data) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 768
        ] as [CFString: Any] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}

#endif
