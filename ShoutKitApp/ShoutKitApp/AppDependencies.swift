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
    let stationConnectionPrewarmer: StationConnectionPrewarmer
    let sleepTimer: SleepTimer
    let settingsStore: SettingsStore
    /// Retained for app lifetime so MetricKit subscription state remains active.
    let diagnosticsService: any DiagnosticsServicing
    let directory: any RadioDirectoryProviding
    /// Retained here so the Observation and Core Location tasks stay alive for
    /// the app's lifetime; it keeps the geo-station filter synchronized with the
    /// feature flag, locale fallback, and optional precise-location override.
    let geoStationLocationCoordinator: GeoStationLocationCoordinator
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

        installSharedNetworking()

        let container = ShoutKitModelContainer.makeContainer()
        let store = LibraryStore(context: container.mainContext)
        let settings = SettingsStore()
        let featureFlags = sharedFeatureFlags()
        let diagnosticsService = makeDiagnosticsService(settings: settings, featureFlags: featureFlags)
        let directoryServices = makeDirectory(settings: settings, featureFlags: featureFlags)
        let directory = directoryServices.directory
        // Route the decorated (preferred + caching) instance through Factory so
        // BrowseViewModel/SearchViewModel resolve it instead of it being threaded
        // manually through RootView.
        registerProductionRadioDirectory(directory)
        let controller = PlaybackController(directory: directory)
        let stationConnectionPrewarmer = StationConnectionPrewarmer()

        configureCallbacks(
            for: controller,
            store: store,
            settings: settings,
            playReporter: directoryServices.playReporter
        )

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
            stationConnectionPrewarmer: stationConnectionPrewarmer,
            sleepTimer: sleepTimer,
            settingsStore: settings,
            diagnosticsService: diagnosticsService,
            directory: directory,
            geoStationLocationCoordinator: directoryServices.geoStationLocationCoordinator,
            activityCoordinator: activityCoordinator,
            stationLaunchRouter: StationLaunchRouter()
        )
        scheduleLaunchWarmups(store: store, featureFlags: featureFlags)

        Self.services = services
        return services
    }

    /// Debug-only Pulse proxying, the latency-tuned shared session, and the
    /// shared URL cache sizing. Must run before anything issues a network
    /// request, since the first touch of `URLSessionHTTPTransport.shared`
    /// locks the session in (first-write-wins, so in Debug the Pulse session
    /// installed first holds the slot — it's built from the same tuned
    /// configuration, so behaviour matches Release either way).
    private static func installSharedNetworking() {
        DebugNetworkInspection.install()

        // Fail-fast when offline, responsive-data service type.
        URLSessionHTTPTransport.installSharedSession(
            URLSession(configuration: URLSessionHTTPTransport.interactiveConfiguration())
        )

        // Size the shared URL cache for RAM-constrained devices: raw bytes
        // (artwork, directory JSON) belong on disk — cheap, and they survive
        // relaunch — while the in-memory tier stays small; decoded bitmaps
        // have their own bounded caches in DesignSystem. Set before the first
        // request, so every `URLSession.shared` consumer picks it up.
        URLCache.shared = URLCache(
            memoryCapacity: 2 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024
        )
    }

    /// Launch-time, fire-and-forget warmups: Spotlight indexing of known
    /// stations (so Siri can resolve "play ⟨station⟩" from a previous session)
    /// and the flag-gated network-path prewarm for the user's top stations.
    private static func scheduleLaunchWarmups(store: LibraryStore, featureFlags: any FeatureFlagProviding) {
        Task {
            await StationEntityQuery().indexKnownStationsForSpotlight()
        }

        // Prewarm skips a cold DNS lookup + TLS handshake on the first tap.
        // A no-op when the user has no snapshotted stations.
        if featureFlags.isEnabled(FeatureCatalog.prewarmStations) {
            let prewarmURLs = store.prewarmStreamURLs(limit: 5)
            if prewarmURLs.isEmpty == false {
                let prewarmer = stationConnectionPrewarmer
                Task.detached(priority: .utility) {
                    await prewarmer.prewarm(streamURLs: prewarmURLs)
                }
            }
        }
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

    /// Constructs the diagnostics service and registers it with Factory.
    /// Extracted from `bootstrap()` to keep that method within the lint
    /// body-length budget.
    private static func makeDiagnosticsService(
        settings: SettingsStore,
        featureFlags: any FeatureFlagProviding
    ) -> DiagnosticsService {
        let diagnosticsService = DiagnosticsService(
            featureFlags: featureFlags,
            settings: settings,
            payloadStore: makeDiagnosticsPayloadStore()
        )
        registerProductionDiagnosticsService(diagnosticsService)
        return diagnosticsService
    }

    /// GRDB-backed on-disk store, falling back to an in-memory store (payloads
    /// lost on relaunch) if the database can't be opened.
    private static func makeDiagnosticsPayloadStore() -> any DiagnosticsPayloadPersisting {
        do {
            return try DiagnosticsPayloadStore()
        } catch {
            assertionFailure("""
            Failed to initialize diagnostics payload store. Falling back to in-memory diagnostics storage, \
            which will be lost on app restart: \(error)
            """)
            print("""
            Diagnostics payload store init error. Falling back to in-memory \
            diagnostics storage (lost on app restart): \(error)
            """)
            return InMemoryDiagnosticsPayloadStore()
        }
    }

    /// The directory stack plus the geo coordinator that keeps its filter in
    /// sync — grouped in a struct (not a tuple) so each member stays named.
    private struct DirectoryServices {
        let directory: any RadioDirectoryProviding
        let playReporter: (any StationPlayReporting)?
        let geoStationLocationCoordinator: GeoStationLocationCoordinator
    }

    private static func makeDirectory(
        settings: SettingsStore,
        featureFlags: any FeatureFlagProviding
    ) -> DirectoryServices {
        let geoFilterProvider = MutableRadioBrowserGeoFilterProvider()
        let geoStationLocationCoordinator = GeoStationLocationCoordinator(
            settings: settings,
            featureFlags: featureFlags,
            geoFilterProvider: geoFilterProvider
        )

        if let apiKey = shoutcastAPIKey() {
            let directory = PreferredRadioDirectory(base: ShoutcastDirectoryClient(apiKey: apiKey))
            return DirectoryServices(
                directory: CachingRadioDirectory(base: directory),
                playReporter: nil,
                geoStationLocationCoordinator: geoStationLocationCoordinator
            )
        }

        let radioBrowser = RadioBrowserDirectoryClient(geoFilterProvider: geoFilterProvider)
        let directory = PreferredRadioDirectory(base: radioBrowser)
        return DirectoryServices(
            directory: CachingRadioDirectory(base: directory),
            playReporter: radioBrowser,
            geoStationLocationCoordinator: geoStationLocationCoordinator
        )
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
