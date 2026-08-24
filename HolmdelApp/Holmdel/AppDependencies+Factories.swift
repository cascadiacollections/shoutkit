import FeatureFlags
import Foundation
import Persistence
import RadioDirectory

// The two service stacks `bootstrap()` doesn't build inline — diagnostics and
// the directory — each of which picks between concrete implementations and
// registers the result with Factory. Kept out of AppDependencies.swift so the
// choices they encode (in-memory fallback, Radio-Browser vs SHOUTcast) stay
// readable next to each other, and so that file stays under the 400-line
// `file_length` limit CI enforces via `swiftlint --strict`. These helpers are
// `internal` only because an extension in another file can't reach `private`
// members; nothing outside `AppDependencies` calls them.

// MARK: - Diagnostics

extension AppDependencies {
    /// Constructs the diagnostics service and registers it with Factory.
    static func makeDiagnosticsService(
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
}

// MARK: - Directory

extension AppDependencies {
    /// The directory stack plus the geo coordinator that keeps its filter in
    /// sync — grouped in a struct (not a tuple) so each member stays named.
    struct DirectoryServices {
        let directory: any RadioDirectoryProviding
        let discoveryCache: any DirectoryDiscoveryCaching
        let playReporter: (any StationPlayReporting)?
        let geoStationLocationCoordinator: GeoStationLocationCoordinator
    }

    /// Routes the directory and its snapshot facet through Factory so the view
    /// models resolve them instead of their being threaded through RootView.
    static func registerProductionDirectory(_ services: DirectoryServices) -> any RadioDirectoryProviding {
        registerProductionRadioDirectory(services.directory)
        registerProductionDiscoveryCache(services.discoveryCache)
        return services.directory
    }

    /// Radio-Browser (free, open source, keyless) is the default discovery
    /// source. Supplying SHOUTCAST_DEV_KEY in Config/Secrets.xcconfig opts into
    /// SHOUTcast's own directory instead. Either base is wrapped in
    /// PreferredRadioDirectory so curated stations (KEXP) always appear first,
    /// then in CachingRadioDirectory so Listen Now and Browse refreshing at launch
    /// share one fetch — and so that fetch is written to disk, letting the next
    /// launch paint stations before (or without) reaching the network.
    static func makeDirectory(
        settings: SettingsStore,
        featureFlags: any FeatureFlagProviding
    ) -> DirectoryServices {
        let geoFilterProvider = MutableRadioBrowserGeoFilterProvider()
        let geoStationLocationCoordinator = GeoStationLocationCoordinator(
            settings: settings,
            featureFlags: featureFlags,
            geoFilterProvider: geoFilterProvider
        )
        // One file serves either branch: snapshots are scoped by source identity.
        let snapshotStore = FileDirectorySnapshotStore.applicationSupport()

        if let apiKey = shoutcastAPIKey() {
            let directory = PreferredRadioDirectory(
                base: ShoutcastDirectoryClient(apiKey: apiKey),
                preferredStations: PreferredStations.all
            )
            let caching = CachingRadioDirectory(
                base: directory,
                snapshotStore: snapshotStore,
                snapshotIdentity: { "shoutcast" }
            )
            return DirectoryServices(
                directory: caching,
                discoveryCache: caching,
                playReporter: nil,
                geoStationLocationCoordinator: geoStationLocationCoordinator
            )
        }

        let radioBrowser = RadioBrowserDirectoryClient(geoFilterProvider: geoFilterProvider, userAgent: "Holmdel/0.1")
        let directory = PreferredRadioDirectory(base: radioBrowser, preferredStations: PreferredStations.all)
        let caching = CachingRadioDirectory(
            base: directory,
            snapshotStore: snapshotStore,
            // Geo-filtered results are only reusable while that filter still applies.
            snapshotIdentity: {
                "radio-browser;" + (await geoFilterProvider.currentGeoFilter()?.snapshotIdentity ?? "unfiltered")
            }
        )
        return DirectoryServices(
            directory: caching,
            discoveryCache: caching,
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
