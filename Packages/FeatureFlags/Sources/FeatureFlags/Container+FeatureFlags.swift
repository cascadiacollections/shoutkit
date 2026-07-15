import FactoryKit
import Foundation

public extension Container {
    /// The app-wide feature-flag service, resolved via Factory so every consumer
    /// shares one observable instance — observation invalidation is per-instance,
    /// so split instances would not see each other's changes. Previews and tests
    /// resolve against a throwaway suite instead of the user's real defaults.
    @MainActor
    var featureFlags: Factory<any FeatureFlagProviding> {
        self { DefaultsFeatureFlagService() }
            .scope(.singleton)
            .onPreview { DefaultsFeatureFlagService(defaults: .ephemeralSuite()) }
            .onTest { DefaultsFeatureFlagService(defaults: .ephemeralSuite()) }
    }
}

/// Resolves the shared feature-flag service. Kept as a free function so callers
/// only need `import FeatureFlags`, not `FactoryKit`, to reach the shared instance.
@MainActor
public func sharedFeatureFlags() -> any FeatureFlagProviding {
    Container.shared.featureFlags()
}

private extension UserDefaults {
    static func ephemeralSuite() -> UserDefaults {
        let name = "featureFlags.ephemeral.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { return .standard }
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
