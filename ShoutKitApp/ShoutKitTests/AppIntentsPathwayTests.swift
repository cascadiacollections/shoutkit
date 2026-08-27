import AppIntentsTesting
import Foundation
import Testing
@testable import ShoutKit

/// Exercises ShoutKit's App Intents through the **real system pathways** using
/// the iOS 27 App Intents Testing framework: `IntentDefinitions` resolves the
/// app's extracted intent/entity metadata and drives it exactly as Siri and
/// Spotlight would, rather than calling `perform()` on a hand-built instance.
///
/// This is an integration test: it boots the app's dependency graph
/// (`AppDependencies.bootstrap()` via `StationEntityQuery`), so it runs on a host
/// (Cmd+U in Xcode, or a simulator/device) — not in the headless `swift test`
/// package suites, which stay unit-level. We deliberately assert against the
/// query's local/curated path (no live directory search) so the test is
/// deterministic and offline-safe.
///
/// NOTE: `IntentDefinitions` looks entries up by the App Intents *type
/// identifier*, which defaults to the Swift type name. If the lookup traps,
/// adjust the string to the identifier Xcode's App Intents metadata assigns to
/// `StationEntity`.
///
/// The suite carries no `@available` guard, and Swift Testing's macros reject
/// one on a suite anyway. That was free when the deployment floor was iOS 27.
/// Since the floor dropped to iOS 26 (DECISIONS.md 2026-08-12) the guard has to
/// live *inside* the test body instead — `AppIntentsTesting`'s `IntentDefinitions`
/// is iOS 27-only, and the whole target failed to build without it. A runtime
/// `guard #available` is what the macros permit, and it costs nothing here
/// because the case is `.disabled` in CI regardless.
@Suite struct AppIntentsPathwayTests {
    /// The `StationEntity` query must surface stations even before the user has
    /// favorited or played anything — the curated `PreferredStations` seed the
    /// suggestions — otherwise Siri has nothing to resolve "play ⟨station⟩"
    /// against on a fresh install.
    ///
    /// Disabled for the CI environment, **not** for #116 — that bug is fixed and
    /// this test helped prove it. Re-enabled against the snapshot-DTO fix, the
    /// `EntityProperty` trap was gone: 8 of the 9 cases passed, including every
    /// one that decodes a cached `StationEntity`. What this case hit instead was
    ///
    ///   Caught error: Underlying session was cancelled. (transportCancelled…)
    ///
    /// `IntentDefinitions` drives the real App Intents system pathway, which
    /// needs a live session with the intents daemon. A headless CI simulator
    /// doesn't reliably provide one, and the cancellation is that session going
    /// away — nothing to do with our entity or its storage. The suite doc above
    /// always said this one wants a host: it is an integration test, and Cmd+U
    /// on a real simulator or device is where it means something.
    ///
    /// Worth knowing for anyone re-enabling it: the failure is cheap but the
    /// aftermath is not. A failed test leaves xcodebuild collecting simulator
    /// diagnostics for a 600 s timeout, so the job runs ~15 min instead of ~8
    /// even though the tests themselves finish in 8 s.
    @Test(.disabled("IntentDefinitions has no live intents session in CI — run it on a host"))
    func stationEntityQuerySuggestsStationsOnAFreshLibrary() async throws {
        // `IntentDefinitions` and the entity accessors it vends are iOS 27-only,
        // and the app's floor is iOS 26 — so the availability check is what keeps
        // this target compiling, not a choice about what to exercise. Below 27
        // there is nothing to assert: the App Intents Testing framework that
        // drives the real system pathway does not exist there.
        guard #available(iOS 27, *) else { return }

        let definitions = IntentDefinitions(bundleIdentifier: "com.cascadiacollections.shoutkit")
        let stationEntity = definitions.entities["StationEntity"]

        let suggestions = try await stationEntity.suggestedEntities()

        #expect(suggestions.isEmpty == false)
    }
}
