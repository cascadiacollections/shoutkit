import DebugSupport
import DesignSystem
import FeatureFlags
import Foundation
import NowPlayingActivityKit
import Observation
import OSLog
import Persistence
import Playback
import RadioDirectory
import CoreLocation
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
        let (directory, playReporter, geoStationLocationCoordinator) = makeDirectory(
            settings: settings,
            featureFlags: featureFlags
        )
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
            directory: directory,
            geoStationLocationCoordinator: geoStationLocationCoordinator,
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

    private static func makeDirectory(
        settings: SettingsStore,
        featureFlags: any FeatureFlagProviding
    ) -> (any RadioDirectoryProviding, (any StationPlayReporting)?, GeoStationLocationCoordinator) {
        let geoFilterProvider = MutableRadioBrowserGeoFilterProvider()
        let geoStationLocationCoordinator = GeoStationLocationCoordinator(
            settings: settings,
            featureFlags: featureFlags,
            geoFilterProvider: geoFilterProvider
        )

        if let apiKey = shoutcastAPIKey() {
            let directory = PreferredRadioDirectory(base: ShoutcastDirectoryClient(apiKey: apiKey))
            return (CachingRadioDirectory(base: directory), nil, geoStationLocationCoordinator)
        }

        let radioBrowser = RadioBrowserDirectoryClient(geoFilterProvider: geoFilterProvider)
        let directory = PreferredRadioDirectory(base: radioBrowser)
        return (CachingRadioDirectory(base: directory), radioBrowser, geoStationLocationCoordinator)
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

@MainActor
final class GeoStationLocationCoordinator: NSObject, CLLocationManagerDelegate {
    private let settings: SettingsStore
    private let featureFlags: any FeatureFlagProviding
    private let geoFilterProvider: MutableRadioBrowserGeoFilterProvider
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let logger = Logger(subsystem: "ShoutKit.App", category: "GeoStationLocationCoordinator")
    private let geoStationsFeature = FeatureCatalog.geoStations
    private var observationTask: Task<Void, Never>?
    private var preciseCountryCode: String?

    init(
        settings: SettingsStore,
        featureFlags: any FeatureFlagProviding,
        geoFilterProvider: MutableRadioBrowserGeoFilterProvider
    ) {
        self.settings = settings
        self.featureFlags = featureFlags
        self.geoFilterProvider = geoFilterProvider
        super.init()
        locationManager.delegate = self
        observeSettings()
        Task { @MainActor [weak self] in
            await self?.refreshFilteringState()
        }
    }

    deinit {
        observationTask?.cancel()
    }

    private func observeSettings() {
        observationTask = Task { [weak self] in
            guard let self else { return }
            let changes = Observations {
                (
                    settings.isPreciseGeoStationLocationEnabled,
                    featureFlags.isEnabled(geoStationsFeature)
                )
            }

            for await _ in changes {
                await refreshFilteringState()
            }
        }
    }

    private func refreshFilteringState() async {
        guard featureFlags.isEnabled(geoStationsFeature) else {
            preciseCountryCode = nil
            await geoFilterProvider.setCurrentGeoFilter(nil)
            return
        }

        if settings.isPreciseGeoStationLocationEnabled {
            refreshPreciseLocationAuthorization()
        } else {
            preciseCountryCode = nil
        }

        await pushCurrentGeoFilter()
    }

    private func refreshPreciseLocationAuthorization() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        case .denied, .restricted:
            preciseCountryCode = nil
        @unknown default:
            preciseCountryCode = nil
        }
    }

    private func pushCurrentGeoFilter() async {
        let preciseCountryOverride = settings.isPreciseGeoStationLocationEnabled ? preciseCountryCode : nil
        let geoFilter = RadioBrowserGeoFilter(
            locale: .current,
            countryCodeOverride: preciseCountryOverride
        )
        await geoFilterProvider.setCurrentGeoFilter(geoFilter)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshPreciseLocationAuthorization()
        Task { @MainActor in
            await pushCurrentGeoFilter()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    self.logger.error("Reverse geocoding failed: \(error.localizedDescription, privacy: .public)")
                } else {
                    self.preciseCountryCode = placemarks?.first?.isoCountryCode
                }
                await self.pushCurrentGeoFilter()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor in
            self.logger.error("Location request failed: \(error.localizedDescription, privacy: .public)")
            self.preciseCountryCode = nil
            await self.pushCurrentGeoFilter()
        }
    }
}
