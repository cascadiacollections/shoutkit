import DebugSupport
import DesignSystem
import FeatureFlags
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
    /// Retained for app lifetime so MetricKit subscription state remains active.
    let diagnosticsService: any DiagnosticsServicing
    let directory: any RadioDirectoryProviding
    /// Retained here: its observation tasks hold it weakly, so this reference
    /// is what keeps the Live Activity following playback for the app's lifetime.
    let activityCoordinator: NowPlayingActivityCoordinator
    let stationLaunchRouter: StationLaunchRouter
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

        // Debug-only: route the shared HTTP transport through Pulse's logging
        // proxy. Must run before anything below issues a network request, since
        // the first touch of `URLSessionHTTPTransport.shared` locks the session in.
        DebugNetworkInspection.install()

        // Size the shared URL cache for RAM-constrained devices: raw bytes
        // (artwork, directory JSON) belong on disk — cheap, and they survive
        // relaunch — while the in-memory tier stays small; decoded bitmaps
        // have their own bounded caches in DesignSystem. Set here, before the
        // first request, so every `URLSession.shared` consumer picks it up.
        URLCache.shared = URLCache(
            memoryCapacity: 2 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024
        )

        let container = ShoutKitModelContainer.makeContainer()
        let store = LibraryStore(context: container.mainContext)
        let settings = SettingsStore()
        let featureFlags = sharedFeatureFlags()
        let diagnosticsPayloadStore: any DiagnosticsPayloadPersisting
        do {
            diagnosticsPayloadStore = try DiagnosticsPayloadStore()
        } catch {
            assertionFailure("""
            Failed to initialize diagnostics payload store. Falling back to in-memory diagnostics storage, \
            which will be lost on app restart: \(error)
            """)
            print("""
            Diagnostics payload store init error. Falling back to in-memory \
            diagnostics storage (lost on app restart): \(error)
            """)
            diagnosticsPayloadStore = InMemoryDiagnosticsPayloadStore()
        }
        let diagnosticsService = DiagnosticsService(
            featureFlags: featureFlags,
            settings: settings,
            payloadStore: diagnosticsPayloadStore
        )
        registerProductionDiagnosticsService(diagnosticsService)
        let (directory, playReporter) = makeDirectory()
        // Route the decorated (preferred + caching) instance through Factory so
        // BrowseViewModel/SearchViewModel resolve it instead of it being threaded
        // manually through RootView.
        registerProductionRadioDirectory(directory)
        let controller = PlaybackController(directory: directory)

        configureCallbacks(for: controller, store: store, settings: settings, playReporter: playReporter)

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
            diagnosticsService: diagnosticsService,
            directory: directory,
            activityCoordinator: activityCoordinator,
            stationLaunchRouter: StationLaunchRouter()
        )
        // Push known stations (favorites, curated, recents) into Spotlight's
        // semantic index once per launch so Siri can resolve "play ⟨station⟩"
        // for a station from a previous session.
        Task {
            await StationEntityQuery().indexKnownStationsForSpotlight()
        }

        Self.services = services
        return services
    }

    /// Radio-Browser (free, open source, keyless) is the default discovery
    /// source. Supplying SHOUTCAST_DEV_KEY in Config/Secrets.xcconfig opts into
    /// SHOUTcast's own directory instead. Either base is wrapped in
    /// PreferredRadioDirectory so curated stations (KEXP) always appear first,
    /// then in CachingRadioDirectory so Listen Now and Browse refreshing at
    /// launch share one fetch instead of hitting the directory twice.
    /// Wires the controller's app-layer callbacks: recents + play reporting on
    /// station change, local listening history on each heard track, and the
    /// gated album-art / Apple Music resolver. Extracted from `bootstrap()` so
    /// that method stays focused on constructing the dependency graph.
    private static func configureCallbacks(
        for controller: PlaybackController,
        store: LibraryStore,
        settings: SettingsStore,
        playReporter: (any StationPlayReporting)?
    ) {
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

        controller.onTrackHeard = { heard in
            store.logRecentlyHeardTrack(
                station: heard.station,
                title: heard.track.title,
                artist: heard.track.artist,
                heardAt: heard.track.receivedAt,
                appleMusicURL: heard.appleMusicURL
            )
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
