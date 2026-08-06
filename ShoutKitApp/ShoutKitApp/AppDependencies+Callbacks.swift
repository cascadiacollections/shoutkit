import DesignSystem
import FeatureFlags
import Foundation
import Persistence
import Playback
import RadioDirectory
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

// Everything that happens *after* the graph exists: the app-layer closures
// `PlaybackController` calls back into, and the watch sync one of them feeds.
// Split out of AppDependencies.swift so `bootstrap()` reads as construction
// only, and for the 400-line `file_length` limit CI enforces via
// `swiftlint --strict`.

extension AppDependencies {
    private static let watchLastStationSync = PhoneWatchLastStationSync()

    /// Wires the controller's app-layer callbacks: recents + play reporting on
    /// station change, local listening history on each heard track, and the
    /// gated album-art / Apple Music resolver.
    static func configureCallbacks(
        for controller: PlaybackController,
        store: LibraryStore,
        settings: SettingsStore,
        featureFlags: any FeatureFlagProviding,
        playReporter: (any StationPlayReporting)?
    ) {
        controller.onStationPlayed = { station in
            store.logRecent(station)
            watchLastStationSync.publish(station: station)
            // Radio-Browser etiquette: report plays so the community directory
            // can rank popularity. Fire-and-forget; never affects playback.
            // User-toggleable in Settings (the README privacy story promises it).
            if settings.isPlayReportingEnabled, let playReporter {
                Task {
                    await playReporter.reportPlay(stationID: station.id)
                }
            }
        }

        controller.onTrackHeard = { heard in
            store.logRecentlyHeardTrack(
                station: heard.station,
                title: heard.track.title,
                artist: heard.track.artist,
                heardAt: heard.track.receivedAt,
                appleMusicURL: heard.appleMusicURL
            )
        }

        controller.tapToAudioPrewarmEnabledProvider = {
            featureFlags.isEnabled(FeatureCatalog.prewarmStations)
        }

        // Best-effort album art + Apple Music link from a single iTunes Search
        // API hit. Gated here, at the source, so opting out stops the
        // supplemental network request itself — the toggle lives under Privacy
        // and must mean what it says. The views also read the setting reactively
        // (flipping it updates the UI immediately); the lock screen follows on
        // the next track change.
        controller.trackResourcesProvider = { track in
            guard settings.isAlbumArtEnabled else { return .none }
            let match = await AlbumArtLookup.lookup(artist: track.artist, title: track.title)
            return TrackResources(artworkURL: match.artworkURL, appleMusicURL: match.appleMusicURL)
        }
    }
}

#if canImport(WatchConnectivity)

private final class PhoneWatchLastStationSync: NSObject, WCSessionDelegate {
    private enum Keys {
        static let lastStation = "watchSync.lastStation"
    }

    private let session: WCSession?
    private let encoder = JSONEncoder()

    override init() {
        if WCSession.isSupported() {
            let session = WCSession.default
            self.session = session
        } else {
            session = nil
        }
        super.init()
        self.session?.delegate = self
        self.session?.activate()
    }

    func publish(station: Station) {
        guard let session,
              session.activationState == .activated,
              session.isWatchAppInstalled else { return }
        guard let encoded = try? encoder.encode(station) else { return }
        try? session.updateApplicationContext([Keys.lastStation: encoded])
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}

#else

private final class PhoneWatchLastStationSync {
    func publish(station: Station) {}
}

#endif
