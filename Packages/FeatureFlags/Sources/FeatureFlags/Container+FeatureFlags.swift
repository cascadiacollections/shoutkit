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
            .onPreview { DefaultsFeatureFlagService.ephemeral() }
            .onTest { DefaultsFeatureFlagService.ephemeral() }
    }
}

/// Resolves the shared feature-flag service. Kept as a free function so callers
/// only need `import FeatureFlags`, not `FactoryKit`, to reach the shared instance.
@MainActor
public func sharedFeatureFlags() -> any FeatureFlagProviding {
    Container.shared.featureFlags()
}

private extension DefaultsFeatureFlagService {
    static func ephemeral() -> DefaultsFeatureFlagService {
        let suiteName = "featureFlags.ephemeral.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure(
                """
                Could not create ephemeral UserDefaults suite '\(suiteName)'. \
                This may indicate insufficient system resources.
                """
            )
        }
        defaults.removePersistentDomain(forName: suiteName)
        return DefaultsFeatureFlagService(
            defaults: defaults,
            cleanupOnDeinit: {
                defaults.removePersistentDomain(forName: suiteName)
            }
        )
    }
}
