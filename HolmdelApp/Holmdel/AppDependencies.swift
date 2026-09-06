import FeatureFlags
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
    /// False when SwiftData failed to open its on-disk store and the app is
    /// running on a fallback in-memory store.
    let isPersistentStoreAvailable: Bool
    let libraryStore: LibraryStore
    let playbackController: PlaybackController
    let stationConnectionPrewarmer: StationConnectionPrewarmer
    let sleepTimer: SleepTimer
    let settingsStore: SettingsStore
    /// Retained for app lifetime so MetricKit subscription state remains active.
    let diagnosticsService: any DiagnosticsServicing
    let directory: any RadioDirectoryProviding
    /// The persisted-snapshot facet of `directory`. Present even when Application
    /// Support can't be resolved — it just has no saved stations to hand back.
    let directoryDiscoveryCache: any DirectoryDiscoveryCaching
    /// Retained here so the Observation and Core Location tasks stay alive for
    /// the app's lifetime; it keeps the geo-station filter synchronized with the
    /// feature flag, locale fallback, and optional precise-location override.
    let geoStationLocationCoordinator: GeoStationLocationCoordinator
    /// Retained here: its observation tasks hold it weakly, so this reference
    /// is what keeps the Live Activity following playback for the app's lifetime.
    let activityCoordinator: NowPlayingActivityCoordinator
    let stationLaunchRouter: StationLaunchRouter
}

// This file is the shared graph and the one call that assembles it. Each step
// `bootstrap()` delegates to lives in its own extension: the networking install
// in AppDependencies+Networking.swift, the diagnostics and directory stacks in
// +Factories.swift, the controller callbacks in +Callbacks.swift, and the
// post-launch warmups in +Warmups.swift. Splitting along those seams keeps this
// file under the 400-line `file_length` limit CI enforces via
// `swiftlint --strict` — the same remedy as the
// AudioStreamingPlaybackEngine+Session and PlaybackController+Internals splits.
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

        installProcessWideServices()

        let container = ShoutKitModelContainer.makeContainer()
        let isPersistentStoreAvailable = ShoutKitModelContainer.isPersistentStoreAvailable
        let store = LibraryStore(context: container.mainContext)
        let settings = SettingsStore()
        let featureFlags = sharedFeatureFlags()
        let diagnosticsService = makeDiagnosticsService(settings: settings, featureFlags: featureFlags)
        let directoryServices = makeDirectory(settings: settings, featureFlags: featureFlags)
        let directory = registerProductionDirectory(directoryServices)
        let controller = PlaybackController(directory: directory)
        let stationConnectionPrewarmer = StationConnectionPrewarmer()

        // A no-op on engines that don't support an equalizer (see
        // `RadioPlaybackEngine.supportsEqualizer`), and safe at `.normal`.
        controller.restoreEqualizerPreset(rawValue: settings.equalizerPresetRawValue)
        // Same no-op contract as above, for engines that don't support
        // `RadioPlaybackEngine.supportsSpatialAudio`.
        controller.restoreSpatialAudioPreference(isEnabled: settings.isSpatialAudioEnabled)

        configureCallbacks(
            for: controller,
            store: store,
            settings: settings,
            featureFlags: featureFlags,
            playReporter: directoryServices.playReporter
        )

        let activityCoordinator = makeActivityCoordinator(for: controller, featureFlags: featureFlags)
        let sleepTimer = makeSleepTimer(for: controller)

        let services = AppServices(
            container: container,
            isPersistentStoreAvailable: isPersistentStoreAvailable,
            libraryStore: store,
            playbackController: controller,
            stationConnectionPrewarmer: stationConnectionPrewarmer,
            sleepTimer: sleepTimer,
            settingsStore: settings,
            diagnosticsService: diagnosticsService,
            directory: directory,
            directoryDiscoveryCache: directoryServices.discoveryCache,
            geoStationLocationCoordinator: directoryServices.geoStationLocationCoordinator,
            activityCoordinator: activityCoordinator,
            stationLaunchRouter: StationLaunchRouter()
        )
        scheduleLaunchWarmups(store: store, featureFlags: featureFlags, prewarmer: stationConnectionPrewarmer)

        Self.services = services
        return services
    }
}
