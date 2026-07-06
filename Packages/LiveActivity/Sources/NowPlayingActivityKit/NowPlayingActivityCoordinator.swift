import ActivityKit
import Foundation
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
/// - stop or failure → end the activity immediately
@MainActor
public final class NowPlayingActivityCoordinator {
    private var activity: Activity<NowPlayingActivityAttributes>?
    private var currentStationID: String?
    private var latestMetadata: NowPlayingMetadata?
    private var observationTasks: [Task<Void, Never>] = []

    public init() {}

    isolated deinit {
        for task in observationTasks {
            task.cancel()
        }
    }

    /// Follows the controller's playback state and live track metadata for the
    /// life of this coordinator. Call once at bootstrap. Values are deduplicated
    /// here: ICY pushes often repeat identical track info, and redundant
    /// ActivityKit updates are wasted IPC.
    public func observe(_ controller: PlaybackController) {
        let states = Observations { controller.state }
        observationTasks.append(Task { [weak self] in
            var previous: PlaybackState?
            for await state in states where state != previous {
                previous = state
                guard let self else { return }
                self.playbackStateChanged(state)
            }
        })

        let tracks = Observations { controller.nowPlaying }
        observationTasks.append(Task { [weak self] in
            var previous: NowPlayingMetadata?
            for await metadata in tracks where metadata != previous {
                previous = metadata
                guard let self else { return }
                self.nowPlayingChanged(metadata)
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
        if let activity, currentStationID == station.id {
            update(activity, isPlaying: isPlaying)
            return
        }

        // Attributes are fixed for an activity's lifetime, so a station switch
        // needs a fresh activity.
        endActivity()

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = NowPlayingActivityAttributes(
            stationName: station.name,
            genre: station.genre
        )
        let content = ActivityContent(
            state: contentState(isPlaying: isPlaying),
            staleDate: nil
        )

        activity = try? Activity.request(attributes: attributes, content: content)
        currentStationID = station.id
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
        currentStationID = nil

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
            isPlaying: isPlaying
        )
    }
}
