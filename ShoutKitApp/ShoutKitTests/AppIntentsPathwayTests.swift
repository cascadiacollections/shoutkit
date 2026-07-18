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
/// No `@available` guard is needed — the app's deployment target is iOS 27, so
/// `AppIntentsTesting` is always available (and Swift Testing's macros reject an
/// `@available` annotation on the suite anyway).
@Suite struct AppIntentsPathwayTests {
    /// The `StationEntity` query must surface stations even before the user has
    /// favorited or played anything — the curated `PreferredStations` seed the
    /// suggestions — otherwise Siri has nothing to resolve "play ⟨station⟩"
    /// against on a fresh install.
    @Test func stationEntityQuerySuggestsStationsOnAFreshLibrary() async throws {
        let definitions = IntentDefinitions(bundleIdentifier: "com.cascadiacollections.shoutkit")
        let stationEntity = definitions.entities["StationEntity"]

        let suggestions = try await stationEntity.suggestedEntities()

        #expect(suggestions.isEmpty == false)
    }
}
