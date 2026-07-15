import Foundation
import Observation
import Testing

@testable import FeatureFlags

@MainActor
struct DefaultsFeatureFlagServiceTests {
    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "DefaultsFeatureFlagServiceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeService(defaults: UserDefaults) -> DefaultsFeatureFlagService {
        DefaultsFeatureFlagService(defaults: defaults)
    }

    @Test func defaultsUseFeatureDefaultValue() throws {
        let defaults = try makeDefaults()
        let service = makeService(defaults: defaults)
        let diagnostics = try #require(FeatureCatalog.all.first(where: { $0.key == "diagnostics" }))

        #expect(service.override(for: diagnostics) == .useDefault)
        #expect(service.isEnabled(diagnostics) == false)
    }

    @Test func overrideTakesPrecedenceOverDefault() throws {
        let defaults = try makeDefaults()
        let service = makeService(defaults: defaults)
        let diagnostics = try #require(FeatureCatalog.all.first(where: { $0.key == "diagnostics" }))

        service.setOverride(.enabled, for: diagnostics)
        #expect(service.override(for: diagnostics) == .enabled)
        #expect(service.isEnabled(diagnostics) == true)

        service.setOverride(.disabled, for: diagnostics)
        #expect(service.override(for: diagnostics) == .disabled)
        #expect(service.isEnabled(diagnostics) == false)
    }

    @Test func overridesPersistAcrossInstances() throws {
        let defaults = try makeDefaults()
        let diagnostics = try #require(FeatureCatalog.all.first(where: { $0.key == "diagnostics" }))

        let service = makeService(defaults: defaults)
        service.setOverride(.enabled, for: diagnostics)

        let reloaded = makeService(defaults: defaults)
        #expect(reloaded.override(for: diagnostics) == .enabled)
        #expect(reloaded.isEnabled(diagnostics) == true)
    }

    @Test func settingUseDefaultRemovesPersistedOverride() throws {
        let defaults = try makeDefaults()
        let service = makeService(defaults: defaults)
        let diagnostics = try #require(FeatureCatalog.all.first(where: { $0.key == "diagnostics" }))

        service.setOverride(.enabled, for: diagnostics)
        service.setOverride(.useDefault, for: diagnostics)

        #expect(service.override(for: diagnostics) == .useDefault)
        #expect(service.isEnabled(diagnostics) == false)
        #expect(defaults.object(forKey: "featureFlags.diagnostics.override") == nil)
    }

    @Test func mutationsNotifyObservers() throws {
        let defaults = try makeDefaults()
        let service = makeService(defaults: defaults)
        let diagnostics = try #require(FeatureCatalog.all.first(where: { $0.key == "diagnostics" }))

        // onChange fires synchronously (willSet) on this actor, so a plain
        // flag box is race-free despite the @Sendable closure requirement.
        final class Flag: @unchecked Sendable {
            var wasInvalidated = false
        }
        let flag = Flag()
        withObservationTracking {
            _ = service.isEnabled(diagnostics)
        } onChange: {
            flag.wasInvalidated = true
        }

        service.setOverride(.enabled, for: diagnostics)

        #expect(flag.wasInvalidated)
    }

    @Test func resetAllClearsAllOverrides() throws {
        let defaults = try makeDefaults()
        let service = makeService(defaults: defaults)
        for feature in FeatureCatalog.all {
            service.setOverride(.enabled, for: feature)
        }

        service.resetAll()

        for feature in FeatureCatalog.all {
            #expect(service.override(for: feature) == .useDefault)
            #expect(service.isEnabled(feature) == feature.defaultEnabled)
        }
    }

    @Test func unknownFeatureDoesNotPersistOrCrash() throws {
        let defaults = try makeDefaults()
        let service = makeService(defaults: defaults)
        let unknown = Feature(
            key: "unknownFeature",
            title: "Unknown",
            summary: "Not in catalog",
            stage: .internalOnly,
            defaultEnabled: true
        )

        service.setOverride(.disabled, for: unknown)

        #expect(service.override(for: unknown) == .useDefault)
        #expect(service.isEnabled(unknown) == true)
        #expect(defaults.object(forKey: "featureFlags.unknownFeature.override") == nil)
    }
}
