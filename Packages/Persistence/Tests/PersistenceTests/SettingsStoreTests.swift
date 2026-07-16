import Foundation
import Testing

@testable import Persistence

@MainActor
struct SettingsStoreTests {
    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "SettingsStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func playReportingDefaultsToEnabled() throws {
        let store = SettingsStore(defaults: try makeDefaults())
        #expect(store.isPlayReportingEnabled == true)
    }

    @Test func togglePersistsAcrossInstances() throws {
        let defaults = try makeDefaults()

        let store = SettingsStore(defaults: defaults)
        store.isPlayReportingEnabled = false

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.isPlayReportingEnabled == false)

        reloaded.isPlayReportingEnabled = true
        let reloadedAgain = SettingsStore(defaults: defaults)
        #expect(reloadedAgain.isPlayReportingEnabled == true)
    }

    @Test func albumArtDefaultsToEnabled() throws {
        let store = SettingsStore(defaults: try makeDefaults())
        #expect(store.isAlbumArtEnabled == true)
    }

    @Test func albumArtTogglePersistsAcrossInstances() throws {
        let defaults = try makeDefaults()

        let store = SettingsStore(defaults: defaults)
        store.isAlbumArtEnabled = false

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.isAlbumArtEnabled == false)

        reloaded.isAlbumArtEnabled = true
        let reloadedAgain = SettingsStore(defaults: defaults)
        #expect(reloadedAgain.isAlbumArtEnabled == true)
    }

    @Test func preciseGeoStationLocationDefaultsToDisabled() throws {
        let store = SettingsStore(defaults: try makeDefaults())
        #expect(store.isPreciseGeoStationLocationEnabled == false)
    }

    @Test func preciseGeoStationLocationTogglePersistsAcrossInstances() throws {
        let defaults = try makeDefaults()

        let store = SettingsStore(defaults: defaults)
        store.isPreciseGeoStationLocationEnabled = true

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.isPreciseGeoStationLocationEnabled == true)

        reloaded.isPreciseGeoStationLocationEnabled = false
        let reloadedAgain = SettingsStore(defaults: defaults)
        #expect(reloadedAgain.isPreciseGeoStationLocationEnabled == false)
    }

    @Test func diagnosticsSharingDefaultsToDisabled() throws {
        let store = SettingsStore(defaults: try makeDefaults())
        #expect(store.isDiagnosticsSharingEnabled == false)
    }

    @Test func diagnosticsSharingTogglePersistsAcrossInstances() throws {
        let defaults = try makeDefaults()

        let store = SettingsStore(defaults: defaults)
        store.isDiagnosticsSharingEnabled = true

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.isDiagnosticsSharingEnabled == true)

        reloaded.isDiagnosticsSharingEnabled = false
        let reloadedAgain = SettingsStore(defaults: defaults)
        #expect(reloadedAgain.isDiagnosticsSharingEnabled == false)
    }
}
