// The fire-and-forget work `bootstrap()` kicks off once the graph is built:
// Spotlight indexing. Nothing here is awaited, and nothing downstream depends
// on it finishing — which is exactly why it reads as its own file. Split out
// of AppDependencies.swift for the 400-line `file_length` limit CI enforces
// via `swiftlint --strict`.

extension AppDependencies {
    /// Launch-time, fire-and-forget warmup: Spotlight indexing of known
    /// stations, so Siri can resolve "play ⟨station⟩" from a previous session.
    static func scheduleLaunchWarmups() {
        Task {
            await StationEntityQuery().indexKnownStationsForSpotlight()
        }
    }
}
