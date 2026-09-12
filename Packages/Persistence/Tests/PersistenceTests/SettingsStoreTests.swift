import Foundation
@testable import Persistence
import Testing

@MainActor
struct SettingsStoreTests {
    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "SettingsStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func `play reporting defaults to enabled`() throws {
        let store = try SettingsStore(defaults: makeDefaults())
        #expect(store.isPlayReportingEnabled == true)
    }

    @Test func `toggle persists across instances`() throws {
        let defaults = try makeDefaults()

        let store = SettingsStore(defaults: defaults)
        store.isPlayReportingEnabled = false

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.isPlayReportingEnabled == false)

        reloaded.isPlayReportingEnabled = true
        let reloadedAgain = SettingsStore(defaults: defaults)
        #expect(reloadedAgain.isPlayReportingEnabled == true)
    }

    @Test func `album art defaults to enabled`() throws {
        let store = try SettingsStore(defaults: makeDefaults())
        #expect(store.isAlbumArtEnabled == true)
    }

    @Test func `album art toggle persists across instances`() throws {
        let defaults = try makeDefaults()

        let store = SettingsStore(defaults: defaults)
        store.isAlbumArtEnabled = false

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.isAlbumArtEnabled == false)

        reloaded.isAlbumArtEnabled = true
        let reloadedAgain = SettingsStore(defaults: defaults)
        #expect(reloadedAgain.isAlbumArtEnabled == true)
    }

    @Test func `precise geo station location defaults to disabled`() throws {
        let store = try SettingsStore(defaults: makeDefaults())
        #expect(store.isPreciseGeoStationLocationEnabled == false)
    }

    @Test func `precise geo station location toggle persists across instances`() throws {
        let defaults = try makeDefaults()

        let store = SettingsStore(defaults: defaults)
        store.isPreciseGeoStationLocationEnabled = true

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.isPreciseGeoStationLocationEnabled == true)

        reloaded.isPreciseGeoStationLocationEnabled = false
        let reloadedAgain = SettingsStore(defaults: defaults)
        #expect(reloadedAgain.isPreciseGeoStationLocationEnabled == false)
    }

    @Test func `diagnostics sharing defaults to disabled`() throws {
        let store = try SettingsStore(defaults: makeDefaults())
        #expect(store.isDiagnosticsSharingEnabled == false)
    }

    @Test func `diagnostics sharing toggle persists across instances`() throws {
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
