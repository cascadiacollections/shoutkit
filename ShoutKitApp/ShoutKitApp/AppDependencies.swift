import DesignSystem
import Foundation
import NowPlayingActivityKit
import Persistence
import Playback
import RadioDirectory
import SwiftData

/// Everything the app constructs exactly once and shares between the SwiftUI
/// scene and App Intents (which run in the same process but outside the view
/// hierarchy, so they can't reach the SwiftUI environment).
@MainActor
struct AppServices {
    let container: ModelContainer
    let libraryStore: LibraryStore
    let playbackController: PlaybackController
    let sleepTimer: SleepTimer
    let settingsStore: SettingsStore
    let directory: any RadioDirectoryProviding
    /// Retained here: its observation tasks hold it weakly, so this reference
    /// is what keeps the Live Activity following playback for the app's lifetime.
    let activityCoordinator: NowPlayingActivityCoordinator
}

@MainActor
enum AppDependencies {
    private(set) static var services: AppServices?

    /// Idempotent: the app root calls this at launch, and App Intents call it in
    /// `perform()` — whichever runs first constructs the shared graph, so an
    /// intent invoked during a cold launch never builds a second PlaybackController
    /// (two AVPlayers would fight over the audio session).
    @discardableResult
    static func bootstrap() -> AppServices {
        if let services {
            return services
        }

        let container = ShoutKitModelContainer.makeContainer()
        let store = LibraryStore(context: container.mainContext)
        let settings = SettingsStore()
        let (directory, playReporter) = makeDirectory()
        let controller = PlaybackController(directory: directory)

        controller.onStationPlayed = { station in
            store.logRecent(station)
            // Radio-Browser etiquette: report plays so the community directory
            // can rank popularity. Fire-and-forget; never affects playback.
            // User-toggleable in Settings (the README privacy story promises it).
            if settings.isPlayReportingEnabled, let playReporter {
                Task {
                    await playReporter.reportPlay(stationID: station.id)
                }
            }
        }

        // Best-effort album art from the iTunes Search API. Gated here, at the
        // source, so opting out stops the supplemental network request itself —
        // the toggle lives under Privacy and must mean what it says. The views
        // also read the setting reactively (flipping it updates the UI
        // immediately); the lock screen follows on the next track change.
        controller.albumArtURLProvider = { track in
            guard settings.isAlbumArtEnabled else { return nil }
            return await AlbumArtLookup.artworkURL(artist: track.artist, title: track.title)
        }

        // Lock screen / Dynamic Island Live Activity follows playback by
        // observing the controller's @Observable state directly.
        let activityCoordinator = NowPlayingActivityCoordinator()
        activityCoordinator.observe(controller)

        // Sleep timer pauses (not stops) playback so the mini-player survives
        // and resuming in the morning is one tap.
        let sleepTimer = SleepTimer()
        sleepTimer.onFire = { [weak controller] in
            controller?.pause()
        }

        let services = AppServices(
            container: container,
            libraryStore: store,
            playbackController: controller,
            sleepTimer: sleepTimer,
            settingsStore: settings,
            directory: directory,
            activityCoordinator: activityCoordinator
        )
        Self.services = services
        return services
    }

    /// Radio-Browser (free, open source, keyless) is the default discovery
    /// source. Supplying SHOUTCAST_DEV_KEY in Config/Secrets.xcconfig opts into
    /// SHOUTcast's own directory instead. Either base is wrapped in
    /// PreferredRadioDirectory so curated stations (KEXP) always appear first,
    /// then in CachingRadioDirectory so Listen Now and Browse refreshing at
    /// launch share one fetch instead of hitting the directory twice.
    private static func makeDirectory() -> (any RadioDirectoryProviding, (any StationPlayReporting)?) {
        if let apiKey = shoutcastAPIKey() {
            let directory = PreferredRadioDirectory(base: ShoutcastDirectoryClient(apiKey: apiKey))
            return (CachingRadioDirectory(base: directory), nil)
        }

        let radioBrowser = RadioBrowserDirectoryClient()
        let directory = PreferredRadioDirectory(base: radioBrowser)
        return (CachingRadioDirectory(base: directory), radioBrowser)
    }

    private static func shoutcastAPIKey() -> String? {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "SHOUTCAST_DEV_KEY") as? String else {
            return nil
        }

        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAPIKey.isEmpty == false, trimmedAPIKey != "$(SHOUTCAST_DEV_KEY)" else {
            return nil
        }

        return trimmedAPIKey
    }
}
