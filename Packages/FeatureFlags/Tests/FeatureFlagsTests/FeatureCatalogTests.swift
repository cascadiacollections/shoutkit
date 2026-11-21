@testable import FeatureFlags
import Foundation
import Testing

struct FeatureCatalogTests {
    @Test
    func `catalog keys are unique`() {
        let keys = FeatureCatalog.all.map(\.key)

        #expect(Set(keys).count == keys.count)
    }

    @Test
    func `named features are in the catalog`() {
        #expect(FeatureCatalog.all.contains(FeatureCatalog.diagnostics))
    }

    /// Internal-only features are opt-in; flipping a default is a
    /// product decision that should show up as a failing test, not slip through.
    @Test
    func `internal features ship disabled`() {
        let internalFeatures = FeatureCatalog.all.filter { $0.stage == .internalOnly }

        #expect(internalFeatures.isEmpty == false)
        #expect(internalFeatures.allSatisfy { $0.defaultEnabled == false })
    }

    /// The raw values are what `defaults read` shows and what persisted overrides
    /// are decoded from, so renaming a case would orphan every stored override.
    @Test
    func `override raw values are stable`() {
        #expect(FeatureOverride.allCases.map(\.rawValue) == ["useDefault", "enabled", "disabled"])
        #expect(FeatureStage.allCases.map(\.rawValue) == ["internalOnly", "beta", "released"])
    }
}

@MainActor
struct FeatureFlagStorageTests {
    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "FeatureFlagStorageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test
    func `override is stored under a readable key`() throws {
        let defaults = try makeDefaults()
        let service = DefaultsFeatureFlagService(defaults: defaults)

        service.setOverride(.disabled, for: FeatureCatalog.diagnostics)

        #expect(defaults.string(forKey: "featureFlags.diagnostics.override") == "disabled")
    }

    @Test
    func `unrecognized stored value falls back to the default`() throws {
        let defaults = try makeDefaults()
        defaults.set("maybe", forKey: "featureFlags.diagnostics.override")
        let service = DefaultsFeatureFlagService(defaults: defaults)

        #expect(service.override(for: FeatureCatalog.diagnostics) == .useDefault)
        #expect(service.isEnabled(FeatureCatalog.diagnostics) == FeatureCatalog.diagnostics.defaultEnabled)
    }

    @Test
    func `stored value for a feature outside the service is ignored`() throws {
        let defaults = try makeDefaults()
        let outsider = Feature(
            key: "outsider",
            title: "Outsider",
            summary: "Not registered with the service.",
            stage: .internalOnly,
            defaultEnabled: false,
        )
        defaults.set("enabled", forKey: "featureFlags.outsider.override")
        let service = DefaultsFeatureFlagService(defaults: defaults, features: [FeatureCatalog.diagnostics])

        #expect(service.override(for: outsider) == .useDefault)
        #expect(service.isEnabled(outsider) == false)
    }

    @Test
    func `reset all leaves other defaults alone`() throws {
        let defaults = try makeDefaults()
        defaults.set("keep", forKey: "unrelated.key")
        let service = DefaultsFeatureFlagService(defaults: defaults)
        service.setOverride(.enabled, for: FeatureCatalog.diagnostics)

        service.resetAll()

        #expect(defaults.string(forKey: "unrelated.key") == "keep")
        #expect(defaults.object(forKey: "featureFlags.diagnostics.override") == nil)
    }

    /// Observation invalidation is per instance, so every consumer has to share
    /// one service for a toggle in Settings to reach the rest of the app.
    @Test
    func `shared service is a single instance`() {
        #expect(sharedFeatureFlags() === sharedFeatureFlags())
    }
}
