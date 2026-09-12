@testable import FeatureFlags
import Foundation
import Observation
import Testing

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

    @Test func `defaults use feature default value`() throws {
        let defaults = try makeDefaults()
        let service = makeService(defaults: defaults)
        let diagnostics = try #require(FeatureCatalog.all.first(where: { $0.key == "diagnostics" }))

        #expect(service.override(for: diagnostics) == .useDefault)
        #expect(service.isEnabled(diagnostics) == false)
    }

    @Test func `override takes precedence over default`() throws {
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

    @Test func `overrides persist across instances`() throws {
        let defaults = try makeDefaults()
        let diagnostics = try #require(FeatureCatalog.all.first(where: { $0.key == "diagnostics" }))

        let service = makeService(defaults: defaults)
        service.setOverride(.enabled, for: diagnostics)

        let reloaded = makeService(defaults: defaults)
        #expect(reloaded.override(for: diagnostics) == .enabled)
        #expect(reloaded.isEnabled(diagnostics) == true)
    }

    @Test func `setting use default removes persisted override`() throws {
        let defaults = try makeDefaults()
        let service = makeService(defaults: defaults)
        let diagnostics = try #require(FeatureCatalog.all.first(where: { $0.key == "diagnostics" }))

        service.setOverride(.enabled, for: diagnostics)
        service.setOverride(.useDefault, for: diagnostics)

        #expect(service.override(for: diagnostics) == .useDefault)
        #expect(service.isEnabled(diagnostics) == false)
        #expect(defaults.object(forKey: "featureFlags.diagnostics.override") == nil)
    }

    @Test func `mutations notify observers`() throws {
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

    @Test func `reset all clears all overrides`() throws {
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

    @Test func `unknown feature does not persist or crash`() throws {
        let defaults = try makeDefaults()
        let service = makeService(defaults: defaults)
        let unknown = Feature(
            key: "unknownFeature",
            title: "Unknown",
            summary: "Not in catalog",
            stage: .internalOnly,
            defaultEnabled: true,
        )

        service.setOverride(.disabled, for: unknown)

        #expect(service.override(for: unknown) == .useDefault)
        #expect(service.isEnabled(unknown) == true)
        #expect(defaults.object(forKey: "featureFlags.unknownFeature.override") == nil)
    }

    @Test func `cleanup hook runs on deinit`() throws {
        let defaults = try makeDefaults()
        final class Flag: @unchecked Sendable {
            var didRun = false
        }
        let flag = Flag()

        var service: DefaultsFeatureFlagService? = DefaultsFeatureFlagService(
            defaults: defaults,
            cleanupOnDeinit: {
                flag.didRun = true
            },
        )
        #expect(service != nil)
        service = nil

        #expect(flag.didRun)
    }
}
