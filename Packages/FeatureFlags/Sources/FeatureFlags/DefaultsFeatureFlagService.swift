import FactoryKit
import Foundation
import Observation

@MainActor
public protocol FeatureFlagProviding: AnyObject {
    func isEnabled(_ feature: Feature) -> Bool
    func override(for feature: Feature) -> FeatureOverride
    func setOverride(_ override: FeatureOverride, for feature: Feature)
    func resetAll()
}

@MainActor
@Observable
public final class DefaultsFeatureFlagService: FeatureFlagProviding {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let features: [Feature]
    @ObservationIgnored private let knownFeatureKeys: Set<String>
    private var revision = 0

    public init(
        defaults: UserDefaults = .standard,
        features: [Feature] = FeatureCatalog.all
    ) {
        self.defaults = defaults
        self.features = features
        knownFeatureKeys = Set(features.map(\.key))
    }

    public func isEnabled(_ feature: Feature) -> Bool {
        switch override(for: feature) {
        case .enabled:
            true
        case .disabled:
            false
        case .useDefault:
            feature.defaultEnabled
        }
    }

    public func override(for feature: Feature) -> FeatureOverride {
        _ = revision
        guard knownFeatureKeys.contains(feature.key) else { return .useDefault }
        return defaults.value(for: overrideKey(for: feature))
    }

    public func setOverride(_ override: FeatureOverride, for feature: Feature) {
        guard knownFeatureKeys.contains(feature.key) else { return }
        defaults.set(override, for: overrideKey(for: feature))
        revision &+= 1
    }

    public func resetAll() {
        for feature in features {
            defaults.removeObject(forKey: overrideKeyName(for: feature.key))
        }
        revision &+= 1
    }

    private func overrideKey(for feature: Feature) -> DefaultsKey<FeatureOverride> {
        DefaultsKey.codable(overrideKeyName(for: feature.key), default: .useDefault)
    }

    private func overrideKeyName(for featureKey: String) -> String {
        "featureFlags.\(featureKey).override"
    }
}

public extension Container {
    @MainActor
    var featureFlags: Factory<any FeatureFlagProviding> {
        self { DefaultsFeatureFlagService() }
            .scope(.singleton)
    }
}
