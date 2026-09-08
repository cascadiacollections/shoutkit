import FeatureFlags
import Persistence
import Playback

// The fire-and-forget work `bootstrap()` kicks off once the graph is built:
// Spotlight indexing and the flag-gated connection prewarm. Nothing here is
// awaited, and nothing downstream depends on it finishing — which is exactly
// why it reads as its own file. Split out of AppDependencies.swift for the
// 400-line `file_length` limit CI enforces via `swiftlint --strict`.

extension AppDependencies {
    /// Launch-time, fire-and-forget warmups: Spotlight indexing of known
    /// stations (so Siri can resolve "play ⟨station⟩" from a previous session)
    /// and the flag-gated network-path prewarm for the user's top stations.
    static func scheduleLaunchWarmups(
        store: LibraryStore,
        featureFlags: any FeatureFlagProviding,
        prewarmer: StationConnectionPrewarmer
    ) {
        Task {
            await StationEntityQuery().indexKnownStationsForSpotlight()
        }

        // Prewarm skips a cold DNS lookup + TLS handshake on the first tap.
        // A no-op when the user has no snapshotted stations.
        if featureFlags.isEnabled(FeatureCatalog.prewarmStations) {
            let prewarmURLs = store.prewarmStreamURLs(limit: 5)
            if prewarmURLs.isEmpty == false {
                Task.detached(priority: .utility) {
                    await prewarmer.prewarm(streamURLs: prewarmURLs)
                }
            }
        }
    }
}
