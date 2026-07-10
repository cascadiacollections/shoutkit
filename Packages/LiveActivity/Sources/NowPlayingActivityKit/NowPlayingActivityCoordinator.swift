import ActivityKit
import AsyncAlgorithms
import CoreGraphics
import Foundation
import ImageIO
import NowPlayingActivityCore
import Observation
import Playback
import RadioDirectory
import UniformTypeIdentifiers

/// Drives the now-playing Live Activity from playback state by observing
/// `PlaybackController`'s `@Observable` state directly (`Observations` async
/// sequences) — the controller has no knowledge of ActivityKit. The coordinator
/// owns the activity lifecycle:
///
/// - play/buffer on a new station → end any old activity, request a fresh one
/// - pause/resume on the same station → update `isPlaying`
/// - live ICY track changes → update the content state
/// - album art resolving (or station art) → stage the bitmap in the App Group
///   container and hand the widget its token
/// - stop or failure → end the activity immediately
@MainActor
public final class NowPlayingActivityCoordinator {
    private var activity: Activity<NowPlayingActivityAttributes>?
    private var currentStation: Station?
    private var latestMetadata: NowPlayingMetadata?

    /// The artwork URL currently reflected in the activity, and the token of the
    /// bitmap staged for it. Kept in step so a redundant push is skipped and a
    /// station switch clears stale art.
    private var latestArtworkURL: URL?
    private var latestArtworkToken: String?

    private var observationTasks: [Task<Void, Never>] = []
    private var artworkTask: Task<Void, Never>?

    /// Live Activity artwork renders no larger than a Dynamic Island tile, so a
    /// small thumbnail is plenty and keeps the App Group file tiny.
    private static let artworkMaxPixelSize = 256

    public init() {}

    isolated deinit {
        for task in observationTasks {
            task.cancel()
        }
        artworkTask?.cancel()
    }

    /// Follows the controller's playback state, live track metadata, and resolved
    /// album art for the life of this coordinator. Call once at bootstrap. Values
    /// are deduplicated (`removeDuplicates()`): ICY pushes often repeat identical
    /// track info, and redundant ActivityKit updates are wasted IPC.
    public func observe(_ controller: PlaybackController) {
        let states = Observations { controller.state }
        observationTasks.append(Task { [weak self] in
            for await state in states.removeDuplicates() {
                guard let self else { return }
                self.playbackStateChanged(state)
            }
        })

        let tracks = Observations { controller.nowPlaying }
        observationTasks.append(Task { [weak self] in
            for await metadata in tracks.removeDuplicates() {
                guard let self else { return }
                self.nowPlayingChanged(metadata)
            }
        })

        // The controller resolves album art asynchronously after a track change;
        // follow it so the widget's art catches up the same way the lock screen
        // and Now Playing screen do.
        let albumArt = Observations { controller.albumArtURL }
        observationTasks.append(Task { [weak self] in
            for await url in albumArt.removeDuplicates() {
                guard let self else { return }
                self.refreshArtwork(albumArtURL: url)
            }
        })
    }

    private func playbackStateChanged(_ state: PlaybackState) {
        switch state {
        case let .loading(station), let .buffering(station), let .playing(station):
            activate(for: station, isPlaying: true)
        case let .paused(station):
            activate(for: station, isPlaying: false)
        case .idle, .failed:
            endActivity()
        }
    }

    private func nowPlayingChanged(_ metadata: NowPlayingMetadata?) {
        latestMetadata = metadata
        guard let activity else { return }

        let isPlaying = activity.content.state.isPlaying
        update(activity, isPlaying: isPlaying)
    }

    // MARK: - Lifecycle

    private func activate(for station: Station, isPlaying: Bool) {
        if let activity, currentStation?.id == station.id {
            update(activity, isPlaying: isPlaying)
            return
        }

        // Attributes are fixed for an activity's lifetime, so a station switch
        // needs a fresh activity.
        endActivity()

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        currentStation = station

        let attributes = NowPlayingActivityAttributes(
            stationName: station.name,
            genre: station.genre
        )
        let content = ActivityContent(
            state: contentState(isPlaying: isPlaying),
            staleDate: nil
        )

        activity = try? Activity.request(attributes: attributes, content: content)

        // Show the station's own art immediately; an album-art hit later swaps it.
        refreshArtwork(albumArtURL: nil)
    }

    private func update(_ activity: Activity<NowPlayingActivityAttributes>, isPlaying: Bool) {
        let state = contentState(isPlaying: isPlaying)
        // ActivityKit's Activity handle is thread-safe but not Sendable-annotated,
        // and update/end are async so the call must leave the main actor.
        nonisolated(unsafe) let activity = activity
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private func endActivity() {
        latestMetadata = nil
        currentStation = nil
        latestArtworkURL = nil
        latestArtworkToken = nil
        artworkTask?.cancel()
        artworkTask = nil
        LiveActivityArtworkStore.purge()

        guard let activity else { return }
        self.activity = nil

        let finalState = contentState(isPlaying: false)
        // See note in update(_:isPlaying:) about the unsafe binding.
        nonisolated(unsafe) let endingActivity = activity
        Task {
            await endingActivity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }

    private func contentState(isPlaying: Bool) -> NowPlayingActivityAttributes.ContentState {
        NowPlayingActivityAttributes.ContentState(
            trackTitle: latestMetadata?.title,
            artist: latestMetadata?.artist,
            artworkToken: latestArtworkToken,
            isPlaying: isPlaying
        )
    }

    // MARK: - Artwork hand-off

    /// Resolves the artwork the widget should show — the resolved album art when
    /// present, otherwise the station's own art — and, if it changed, stages the
    /// bitmap in the shared container and re-pushes the activity with its token.
    private func refreshArtwork(albumArtURL: URL?) {
        guard activity != nil else { return }
        let targetURL = albumArtURL ?? currentStation?.artworkURL
        guard targetURL != latestArtworkURL else { return }
        latestArtworkURL = targetURL
        artworkTask?.cancel()

        guard let targetURL else {
            // No art at all: clear the token so the widget shows its glyph.
            latestArtworkToken = nil
            pushArtworkUpdate()
            return
        }

        let token = LiveActivityArtworkStore.token(for: targetURL)

        // Already staged (a prior track, or the station art we cached earlier):
        // adopt it without a refetch.
        if LiveActivityArtworkStore.fileURL(forToken: token) != nil {
            latestArtworkToken = token
            pushArtworkUpdate()
            return
        }

        // Drop the stale token now so the widget doesn't show the previous
        // track's art while this one downloads.
        latestArtworkToken = nil
        pushArtworkUpdate()

        artworkTask = Task { [weak self] in
            guard await Self.stageArtwork(from: targetURL, token: token) else { return }
            guard let self, Task.isCancelled == false, self.latestArtworkURL == targetURL else { return }
            self.latestArtworkToken = token
            self.pushArtworkUpdate()
        }
    }

    private func pushArtworkUpdate() {
        guard let activity else { return }
        update(activity, isPlaying: activity.content.state.isPlaying)
    }

    /// Downloads, downsample-decodes, and stages artwork in the shared container —
    /// all off the main actor. The downsample mirrors the lock-screen downsampler
    /// (see `NowPlayingCenter`): an oversized station favicon must not pin a
    /// native-resolution decode, and the staged file stays small.
    /// - Returns: `true` once the PNG is written and readable by the widget.
    private nonisolated static func stageArtwork(from url: URL, token: String) async -> Bool {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return false }
        return await Task.detached(priority: .utility) {
            guard let png = encodePNG(downsampling: data, maxPixelSize: artworkMaxPixelSize) else {
                return false
            }
            return LiveActivityArtworkStore.stage(png, forToken: token) != nil
        }.value
    }

    private nonisolated static func encodePNG(downsampling data: Data, maxPixelSize: Int) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as [CFString: Any] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return encoded as Data
    }
}
