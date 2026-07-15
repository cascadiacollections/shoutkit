import Foundation
import Observation

@MainActor
public protocol FeatureFlagProviding: AnyObject {
    func isEnabled(_ feature: Feature) -> Bool
    func override(for feature: Feature) -> FeatureOverride
    func setOverride(_ override: FeatureOverride, for feature: Feature)
    func resetAll()
}

/// UserDefaults-backed flag store. An override persists as the raw
/// `FeatureOverride` string under `featureFlags.<key>.override` (inspectable
/// with `defaults read`); `.useDefault` removes the entry instead of storing
/// it, so a persisted value always means an explicit override.
@MainActor
@Observable
public final class DefaultsFeatureFlagService: FeatureFlagProviding {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let features: [Feature]
    @ObservationIgnored private let knownFeatureKeys: Set<String>
    /// Bumped on every mutation; reads touch it so `@Observable` tracking
    /// invalidates observers even though the values live in UserDefaults.
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
        guard knownFeatureKeys.contains(feature.key),
              let raw = defaults.string(forKey: overrideKeyName(for: feature.key)),
              let stored = FeatureOverride(rawValue: raw)
        else { return .useDefault }
        return stored
    }

    public func setOverride(_ override: FeatureOverride, for feature: Feature) {
        guard knownFeatureKeys.contains(feature.key) else { return }
        let keyName = overrideKeyName(for: feature.key)
        if override == .useDefault {
            defaults.removeObject(forKey: keyName)
        } else {
            defaults.set(override.rawValue, forKey: keyName)
        }
        revision &+= 1
    }

    public func resetAll() {
        for feature in features {
            defaults.removeObject(forKey: overrideKeyName(for: feature.key))
        }
        revision &+= 1
    }

    private func overrideKeyName(for featureKey: String) -> String {
        "featureFlags.\(featureKey).override"
    }
}
