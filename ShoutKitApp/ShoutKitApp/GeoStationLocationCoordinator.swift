import CoreLocation
import FeatureFlags
import Foundation
import Observation
import OSLog
import Persistence
import RadioDirectory

// @preconcurrency: CLLocationManagerDelegate's requirements are nonisolated,
// but the manager is created on the main actor, so Core Location delivers its
// callbacks on the main run loop — the conformance's runtime isolation check
// always holds.
@MainActor
final class GeoStationLocationCoordinator: NSObject, @preconcurrency CLLocationManagerDelegate {
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
                    self.settings.isPreciseGeoStationLocationEnabled,
                    self.featureFlags.isEnabled(self.geoStationsFeature)
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
        // Re-check the flag: async delegate/geocoder callbacks can land after
        // the feature was turned off, and must not re-install a filter.
        guard featureFlags.isEnabled(geoStationsFeature) else {
            await geoFilterProvider.setCurrentGeoFilter(nil)
            return
        }

        let preciseCountryOverride = settings.isPreciseGeoStationLocationEnabled ? preciseCountryCode : nil
        let geoFilter = RadioBrowserGeoFilter(
            locale: .current,
            countryCodeOverride: preciseCountryOverride
        )
        await geoFilterProvider.setCurrentGeoFilter(geoFilter)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Core Location invokes this as soon as the delegate is assigned (i.e.
        // at every launch). Without the opt-in gate, the `.notDetermined`
        // branch below would prompt for location permission on first launch
        // even though the user never enabled precise geo stations.
        guard featureFlags.isEnabled(geoStationsFeature),
              settings.isPreciseGeoStationLocationEnabled else { return }

        refreshPreciseLocationAuthorization()
        Task {
            await pushCurrentGeoFilter()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
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
