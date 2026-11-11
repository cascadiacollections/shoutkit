import Foundation
import ImageIODownsample
import NowPlayingActivityCore
import Observation
import Playback
import RadioDirectory
import WidgetKit

/// Keeps the Quick Play widget's now-playing snapshot in step with playback.
///
/// Like ``NowPlayingActivityCoordinator`` it observes `PlaybackController`
/// directly, and the controller knows nothing about widgets. Unlike it, this runs
/// whether or not the Live Activity feature is on, and it stages artwork in its
/// own ``NowPlayingWidgetStore`` so neither coordinator's purges can delete the
/// other's files.
///
/// The artwork is the same choice every other now-playing surface makes: the
/// resolved album art when there is one (the album-art privacy toggle is applied
/// at the source, so it is `nil` when the listener opted out), otherwise the
/// station's own art, otherwise nothing and the widget shows its glyph. It is
/// fetched through `imageData(for:)`, so a station whose icon URL now serves a
/// web page falls back to the glyph instead of an undecodable file.
@MainActor
public final class NowPlayingWidgetCoordinator {
    private var station: Station?
    private var status: NowPlayingWidgetSnapshot.PlaybackStatus = .stopped
    private var metadata: NowPlayingMetadata?
    private var albumArtURL: URL?

    /// The artwork URL currently adopted, and its staged token. `artworkURL` is
    /// reset after a failed fetch so the next event (or heartbeat) retries it.
    private var artworkURL: URL?
    private var artworkToken: String?
    private var artworkTask: Task<Void, Never>?

    private var lastPublished: NowPlayingWidgetSnapshot?
    private var lastReload: Date?
    /// Token the widget was last reloaded with. Its file is kept through the
    /// next purge, since WidgetKit may still render that entry until the new
    /// timeline lands.
    private var tokenAtLastReload: String?
    private var deferredReload: Task<Void, Never>?
    private var deferredReloadDate: Date?
    private var heartbeat: Task<Void, Never>?
    private var observationTasks: [Task<Void, Never>] = []

    private let transport: any HTTPTransporting
    private let reloadWidget: @MainActor () -> Void

    /// Large enough for the medium family's artwork tile at 3x, small enough to
    /// keep the App Group file a few hundred KB at most.
    private nonisolated static let artworkMaxPixelSize = 400

    /// How often the snapshot's `updatedAt` is refreshed while a station is
    /// loaded. Comfortably inside `NowPlayingWidgetSnapshot.maximumAge`, and only
    /// a file write: a heartbeat never reloads the widget on its own.
    static let heartbeatInterval: Duration = .seconds(5 * 60)

    public init(
        transport: any HTTPTransporting = URLSessionHTTPTransport.nowPlayingArtwork,
        reloadWidget: @escaping @MainActor () -> Void = {
            WidgetCenter.shared.reloadTimelines(ofKind: QuickPlayFavoritesStore.widgetKind)
        },
    ) {
        self.transport = transport
        self.reloadWidget = reloadWidget
    }

    isolated deinit {
        for task in observationTasks {
            task.cancel()
        }
        artworkTask?.cancel()
        deferredReload?.cancel()
        heartbeat?.cancel()
    }

    /// Follows playback for the life of this coordinator. Call once at bootstrap.
    public func observe(_ controller: PlaybackController) {
        let states = Observations { controller.state }
        observationTasks.append(Task { [weak self] in
            var changes = ChangeFilter<PlaybackState>()
            for await state in states where changes.isNew(state) {
                guard let self else { return }
                self.playbackStateChanged(state)
            }
        })

        let tracks = Observations { controller.nowPlaying }
        observationTasks.append(Task { [weak self] in
            var changes = ChangeFilter<NowPlayingMetadata?>()
            for await metadata in tracks where changes.isNew(metadata) {
                guard let self else { return }
                self.metadata = metadata
                self.refreshArtwork()
                self.publish()
            }
        })

        let albumArt = Observations { controller.albumArtURL }
        observationTasks.append(Task { [weak self] in
            var changes = ChangeFilter<URL?>()
            for await url in albumArt where changes.isNew(url) {
                guard let self else { return }
                self.albumArtURL = url
                self.refreshArtwork()
                self.publish()
            }
        })
    }

    // MARK: - Playback

    private func playbackStateChanged(_ state: PlaybackState) {
        switch state {
        case let .loading(station), let .buffering(station), let .playing(station):
            stationChanged(to: station, status: .playing)
        case let .paused(station):
            stationChanged(to: station, status: .paused)
        case .idle, .failed:
            status = .stopped
            stopHeartbeat()
            publish()
        }
    }

    private func stationChanged(to newStation: Station, status newStatus: NowPlayingWidgetSnapshot.PlaybackStatus) {
        if station?.id != newStation.id {
            // The previous station's album art must not carry over; the
            // controller clears its own copy on a fresh start too.
            albumArtURL = nil
        }
        station = newStation
        status = newStatus
        startHeartbeatIfNeeded()
        refreshArtwork()
        publish()
    }

    // MARK: - Snapshot

    private func publish() {
        guard let station else { return }
        // Only this station's track: metadata observed just before a station
        // switch lands can still belong to the previous one.
        let track = metadata?.stationID == station.id ? metadata : nil
        let link = StationLink(station: station, autoPlay: true, presentNowPlaying: true)
        let snapshot = NowPlayingWidgetSnapshot(
            stationID: station.id,
            stationName: station.name,
            trackTitle: track?.title,
            artist: track?.artist,
            artworkToken: artworkToken,
            status: status,
            deepLinkURLString: link.url().absoluteString,
            updatedAt: Date(),
        )
        NowPlayingWidgetStore.save(snapshot)

        let decision = NowPlayingWidgetReloadPolicy.decide(
            previous: lastPublished,
            next: snapshot,
            lastReload: lastReload,
            now: snapshot.updatedAt,
        )
        lastPublished = snapshot
        switch decision {
        case .reloadNow:
            reloadNow()
        case let .reloadAt(date):
            scheduleReload(at: date)
        case .skip:
            break
        }
    }

    private func reloadNow() {
        deferredReload?.cancel()
        deferredReload = nil
        deferredReloadDate = nil
        lastReload = Date()
        let keep = [artworkToken, tokenAtLastReload].compactMap(\.self)
        tokenAtLastReload = artworkToken
        reloadWidget()
        NowPlayingWidgetStore.purgeArtwork(keeping: Set(keep))
    }

    /// One pending reload at a time, at the earliest date asked for. The
    /// snapshot file already holds the latest state, so the reload shows
    /// whatever is current when it fires, not what was current when it was
    /// scheduled: changes that land before it are folded in for free.
    private func scheduleReload(at date: Date) {
        if let pending = deferredReloadDate, pending <= date {
            return
        }
        deferredReload?.cancel()
        deferredReloadDate = date
        let delay = max(date.timeIntervalSinceNow, 0)
        deferredReload = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard Task.isCancelled == false, let self else { return }
            self.deferredReload = nil
            self.deferredReloadDate = nil
            self.reloadNow()
        }
    }

    private func startHeartbeatIfNeeded() {
        guard heartbeat == nil else { return }
        heartbeat = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(for: Self.heartbeatInterval)
                guard Task.isCancelled == false, let self else { return }
                // Also the retry hook for artwork that failed to fetch, for
                // stations with no track changes to trigger one (KEXP's stream
                // sends no titles).
                self.refreshArtwork()
                self.publish()
            }
        }
    }

    private func stopHeartbeat() {
        heartbeat?.cancel()
        heartbeat = nil
    }

    // MARK: - Artwork

    private func refreshArtwork() {
        let target = albumArtURL ?? station?.artworkURL
        guard target != artworkURL else { return }
        artworkURL = target
        artworkTask?.cancel()

        guard let target else {
            artworkToken = nil
            return
        }

        let token = LiveActivityArtworkStore.token(for: target)
        if NowPlayingWidgetStore.artworkFileURL(forToken: token) != nil {
            artworkToken = token
            return
        }

        // Nothing for the new target yet. Fall back to the station's own art if
        // it's already staged (the usual case between tracks: the controller
        // clears album art at a track change before resolving the next), else
        // the glyph, rather than leave the previous track's cover beside the
        // new title.
        artworkToken = station?.artworkURL
            .map(LiveActivityArtworkStore.token(for:))
            .flatMap { NowPlayingWidgetStore.artworkFileURL(forToken: $0) != nil ? $0 : nil }

        let transport = self.transport
        artworkTask = Task { [weak self] in
            let staged = await Self.stageArtwork(from: target, token: token, transport: transport)
            guard Task.isCancelled == false, let self, self.artworkURL == target else { return }
            guard staged else {
                // Forget it so the next event or heartbeat tries again.
                self.artworkURL = nil
                return
            }
            self.artworkToken = token
            self.publish()
        }
    }

    private nonisolated static func stageArtwork(
        from url: URL,
        token: String,
        transport: any HTTPTransporting,
    ) async -> Bool {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let data = try? await transport.imageData(for: request) else { return false }
        return await Task.detached(priority: .utility) {
            guard let png = ImageIODownsampler.encode(
                data,
                maxPixelSize: CGFloat(artworkMaxPixelSize),
                outputType: .png,
            ) else { return false }
            return NowPlayingWidgetStore.stageArtwork(png, forToken: token)
        }.value
    }
}
