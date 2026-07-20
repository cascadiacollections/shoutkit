import ActivityKit
import AsyncAlgorithms
import CoreGraphics
import Foundation
import ImageIODownsample
import NowPlayingActivityCore
import Observation
import Playback
import RadioDirectory

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

    /// The play/pause flag last *requested*, tracked locally like
    /// `latestMetadata`. `activity.content.state.isPlaying` lags the
    /// fire-and-forget update tasks, so reading it back would let a track or
    /// artwork push resurrect a stale "playing" onto a just-paused activity.
    private var latestIsPlaying = false

    /// Tail of the ActivityKit update chain. `Activity.update`/`end` are
    /// async and fired from unstructured tasks; chaining each onto the
    /// previous keeps them applying in the order they were requested.
    private var updateTask: Task<Void, Never>?

    /// The artwork URL currently reflected in the activity, and the token of the
    /// bitmap staged for it. Kept in step so a redundant push is skipped and a
    /// station switch clears stale art.
    private var latestArtworkURL: URL?
    private var latestArtworkToken: String?

    /// The token whose download/staging is still in flight. Spared from purges
    /// so a purge running between the file write and the adoption on the main
    /// actor can't delete the PNG the adoption is about to point the activity at.
    private var pendingArtworkToken: String?

    /// The album-art URL last observed from the controller, remembered so
    /// playback/track events can re-run ``refreshArtwork()`` — that re-run is
    /// what retries a download that failed transiently (see the failure path
    /// in `refreshArtwork()`), mirroring how the lock-screen center retries on
    /// its next `update`.
    private var latestAlbumArtURL: URL?

    private var observationTasks: [Task<Void, Never>] = []
    private var artworkTask: Task<Void, Never>?
    private let transport: any HTTPTransporting

    /// Live Activity artwork renders no larger than a Dynamic Island tile, so a
    /// small thumbnail is plenty and keeps the App Group file tiny. `nonisolated`
    /// so the off-main staging path can read it.
    private nonisolated static let artworkMaxPixelSize = 256

    public init(transport: any HTTPTransporting = URLSessionHTTPTransport.shared) {
        self.transport = transport
    }

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
                self.albumArtChanged(url)
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

        update(activity, isPlaying: latestIsPlaying)
        // Give a transiently failed artwork download another chance on the
        // next track event; a no-op whenever the current art is already staged.
        refreshArtwork()
    }

    private func albumArtChanged(_ url: URL?) {
        latestAlbumArtURL = url
        refreshArtwork()
    }

    // MARK: - Lifecycle

    private func activate(for station: Station, isPlaying: Bool) {
        latestIsPlaying = isPlaying
        if let activity, currentStation?.id == station.id {
            update(activity, isPlaying: isPlaying)
            // Retry hook for a transiently failed artwork download; a no-op
            // whenever the current art is already staged.
            refreshArtwork()
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

        // Show the station's own art immediately; an album-art hit later swaps
        // it. (`latestAlbumArtURL` was cleared by `endActivity()` above — a
        // station switch invalidates the previous track's art, same as the
        // controller clearing `albumArtURL` on a fresh start.)
        refreshArtwork()
    }

    private func update(_ activity: Activity<NowPlayingActivityAttributes>, isPlaying: Bool) {
        let state = contentState(isPlaying: isPlaying)
        // ActivityKit's Activity handle is thread-safe but not Sendable-annotated,
        // and update/end are async so the call must leave the main actor.
        nonisolated(unsafe) let activity = activity
        let previous = updateTask
        updateTask = Task { [weak self] in
            // Chain onto the previous request so updates apply in the order
            // they were made — two unstructured tasks have no ordering of
            // their own, and a reordered pair could leave a stale state (an
            // old "playing") as the last one applied.
            await previous?.value
            await activity.update(ActivityContent(state: state, staleDate: nil))
            // Purge only now, after the state referencing the current token has
            // been applied. Purging at adoption time deletes the PNG the
            // still-applied previous state points at, and any surface that
            // re-renders in that window (the widget reads the file lazily at
            // render time) falls back to the glyph — visibly out of step with
            // the other now-playing surfaces.
            self?.purgeStagedArtwork(keepingApplied: state.artworkToken)
        }
    }

    private func endActivity() {
        latestMetadata = nil
        currentStation = nil
        latestAlbumArtURL = nil
        latestArtworkURL = nil
        latestArtworkToken = nil
        pendingArtworkToken = nil
        artworkTask?.cancel()
        artworkTask = nil

        guard let activity else {
            // Nothing on screen can reference a staged file; safe to sweep now.
            purgeStagedArtwork(keepingApplied: nil)
            return
        }
        self.activity = nil

        let finalState = contentState(isPlaying: false)
        // See note in update(_:isPlaying:) about the unsafe binding.
        nonisolated(unsafe) let endingActivity = activity
        let previous = updateTask
        updateTask = Task { [weak self] in
            // Keep the end ordered after any in-flight updates for the same
            // activity; a replacement activity's updates simply chain after
            // it, which is harmless.
            await previous?.value
            await endingActivity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
            // Sweep only after the activity is actually gone — it can still
            // re-render its last state until the end applies. Anything a
            // replacement activity staged meanwhile is kept.
            self?.purgeStagedArtwork(keepingApplied: nil)
        }
    }

    /// Drops staged artwork files that nothing can reference anymore, keeping
    /// the token in the activity state that was just applied, the token
    /// currently adopted, and any download still in flight. Runs on the main
    /// actor, where adoptions are serialized, so the keep-set can't go stale
    /// mid-purge.
    private func purgeStagedArtwork(keepingApplied appliedToken: String?) {
        let keep = [appliedToken, latestArtworkToken, pendingArtworkToken].compactMap(\.self)
        LiveActivityArtworkStore.purge(keeping: Set(keep))
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

    /// Resolves the artwork the widget should show — the last observed album
    /// art when present, otherwise the station's own art — and, if it changed,
    /// stages the bitmap in the shared container and re-pushes the activity
    /// with its token. Stale files are NOT purged here; that happens in the
    /// chained update task after the new state has actually been applied (see
    /// `update(_:isPlaying:)`), so a surface re-rendering the previous state
    /// never finds its file already deleted.
    private func refreshArtwork() {
        guard activity != nil else { return }
        let targetURL = latestAlbumArtURL ?? currentStation?.artworkURL
        guard targetURL != latestArtworkURL else { return }
        latestArtworkURL = targetURL
        artworkTask?.cancel()
        pendingArtworkToken = nil

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

        pendingArtworkToken = token
        artworkTask = Task { [weak self] in
            guard let self else { return }
            let staged = await self.stageArtwork(from: targetURL, token: token)
            guard Task.isCancelled == false, self.latestArtworkURL == targetURL else { return }
            self.pendingArtworkToken = nil
            guard staged else {
                // Forget the failed URL so the next playback/track event's
                // `refreshArtwork()` retries it — a transient network error
                // must not leave the activity artless for the whole track
                // while the lock screen (which retries on its next update)
                // recovers, drifting the two surfaces apart.
                self.latestArtworkURL = nil
                return
            }
            self.latestArtworkToken = token
            self.pushArtworkUpdate()
        }
    }

    private func pushArtworkUpdate() {
        guard let activity else { return }
        update(activity, isPlaying: latestIsPlaying)
    }

    /// Downloads, downsample-decodes, and stages artwork in the shared container —
    /// all off the main actor. The downsample mirrors the lock-screen downsampler
    /// (see `NowPlayingCenter`): an oversized station favicon must not pin a
    /// native-resolution decode, and the staged file stays small.
    /// - Returns: `true` once the PNG is written and readable by the widget.
    private func stageArtwork(from url: URL, token: String) async -> Bool {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let data = try? await transport.data(for: request) else { return false }
        let png = await Task.detached(priority: .utility) {
            Self.encodePNG(downsampling: data, maxPixelSize: Self.artworkMaxPixelSize)
        }.value
        // Re-check between the detached encode (which can't observe the outer
        // task's cancellation) and the write, so a superseded download doesn't
        // stage a stale file after its replacement already ran.
        guard let png, Task.isCancelled == false else { return false }
        return await Task.detached(priority: .utility) {
            LiveActivityArtworkStore.stage(png, forToken: token) != nil
        }.value
    }

    private nonisolated static func encodePNG(downsampling data: Data, maxPixelSize: Int) -> Data? {
        ImageIODownsampler.encode(data, maxPixelSize: CGFloat(maxPixelSize), outputType: .png)
    }
}
