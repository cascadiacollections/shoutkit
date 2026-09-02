import FeatureFlags
import Foundation
import Observation
import Testing

@testable import Persistence

@MainActor
struct DiagnosticsServiceTests {
    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "DiagnosticsServiceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Observable
    @MainActor
    fileprivate final class FeatureFlagsStub: FeatureFlagProviding {
        var enabled = false

        func isEnabled(_: Feature) -> Bool { enabled }
        func override(for _: Feature) -> FeatureOverride { .useDefault }
        func setOverride(_: FeatureOverride, for _: Feature) {}
        func resetAll() {}
    }

    @Test func noCollectionWhenFeatureFlagDisabled() throws {
        let settings = SettingsStore(defaults: try makeDefaults())
        settings.isDiagnosticsSharingEnabled = true
        let featureFlags = FeatureFlagsStub()
        featureFlags.enabled = false
        let payloadStore = InMemoryDiagnosticsPayloadStore()
        var subscribeCalls = 0
        let service = DiagnosticsService(
            featureFlags: featureFlags,
            settings: settings,
            payloadStore: payloadStore,
            subscribe: { _ in subscribeCalls += 1 },
            unsubscribe: { _ in }
        )

        // A nil task is the real assertion: no work was even scheduled. The
        // store being empty on its own would also hold if a task had been
        // spawned and simply hadn't run yet.
        let ingestTask = service.ingest(
            metricPayloads: [Data("metric".utf8)],
            diagnosticPayloads: [Data("diag".utf8)]
        )

        #expect(ingestTask == nil)
        #expect(subscribeCalls == 0)
        #expect(payloadStore.metricPayloads.isEmpty)
        #expect(payloadStore.diagnosticPayloads.isEmpty)
    }

    @Test func noCollectionWhenUserOptInDisabled() throws {
        let settings = SettingsStore(defaults: try makeDefaults())
        settings.isDiagnosticsSharingEnabled = false
        let featureFlags = FeatureFlagsStub()
        featureFlags.enabled = true
        let payloadStore = InMemoryDiagnosticsPayloadStore()
        var subscribeCalls = 0
        let service = DiagnosticsService(
            featureFlags: featureFlags,
            settings: settings,
            payloadStore: payloadStore,
            subscribe: { _ in subscribeCalls += 1 },
            unsubscribe: { _ in }
        )

        let ingestTask = service.ingest(
            metricPayloads: [Data("metric".utf8)],
            diagnosticPayloads: [Data("diag".utf8)]
        )

        #expect(ingestTask == nil)
        #expect(subscribeCalls == 0)
        #expect(payloadStore.metricPayloads.isEmpty)
        #expect(payloadStore.diagnosticPayloads.isEmpty)
    }

    @Test func collectionStartsWhenFlagAndOptInEnabled() async throws {
        let settings = SettingsStore(defaults: try makeDefaults())
        settings.isDiagnosticsSharingEnabled = true
        let featureFlags = FeatureFlagsStub()
        featureFlags.enabled = true
        let payloadStore = InMemoryDiagnosticsPayloadStore()
        var subscribeCalls = 0
        let service = DiagnosticsService(
            featureFlags: featureFlags,
            settings: settings,
            payloadStore: payloadStore,
            subscribe: { _ in subscribeCalls += 1 },
            unsubscribe: { _ in }
        )

        // Awaiting the returned task is what makes this deterministic: the
        // persist happens on a `.utility` Task, and polling for its side
        // effects lost the scheduler race under CI's parallel execution.
        let ingestTask = service.ingest(
            metricPayloads: [Data("metric".utf8)],
            diagnosticPayloads: [Data("diag".utf8)]
        )
        try await #require(ingestTask).value

        #expect(subscribeCalls == 1)
        #expect(payloadStore.metricPayloads.count == 1)
        #expect(payloadStore.diagnosticPayloads.count == 1)
    }

    @Test func refreshUnsubscribesWhenOptInTurnsOff() throws {
        let settings = SettingsStore(defaults: try makeDefaults())
        settings.isDiagnosticsSharingEnabled = true
        let featureFlags = FeatureFlagsStub()
        featureFlags.enabled = true
        let payloadStore = InMemoryDiagnosticsPayloadStore()
        var unsubscribeCalls = 0
        let service = DiagnosticsService(
            featureFlags: featureFlags,
            settings: settings,
            payloadStore: payloadStore,
            subscribe: { _ in },
            unsubscribe: { _ in unsubscribeCalls += 1 }
        )

        settings.isDiagnosticsSharingEnabled = false
        service.refreshSubscription()

        #expect(unsubscribeCalls == 1)
        #expect(service.subscribedForCollection == false)
    }

    @Test func refreshesSubscriptionWhenFeatureFlagChanges() async throws {
        let settings = SettingsStore(defaults: try makeDefaults())
        settings.isDiagnosticsSharingEnabled = true
        let featureFlags = FeatureFlagsStub()
        featureFlags.enabled = false
        let payloadStore = InMemoryDiagnosticsPayloadStore()
        var subscribeCalls = 0
        var unsubscribeCalls = 0
        let service = DiagnosticsService(
            featureFlags: featureFlags,
            settings: settings,
            payloadStore: payloadStore,
            subscribe: { _ in subscribeCalls += 1 },
            unsubscribe: { _ in unsubscribeCalls += 1 }
        )

        #expect(service.subscribedForCollection == false)

        featureFlags.enabled = true
        await waitUntil { service.subscribedForCollection }
        #expect(subscribeCalls == 1)

        featureFlags.enabled = false
        await waitUntil { service.subscribedForCollection == false }
        #expect(unsubscribeCalls == 1)
    }

    /// Polls until `condition` holds. Only
    /// `refreshesSubscriptionWhenFeatureFlagChanges` still needs this, and only
    /// because there is no way to await an `Observations` hop directly — the
    /// point of that test is that the observation is wired up at all, so
    /// calling `refreshSubscription()` by hand would assert nothing.
    ///
    /// Everything else here is now deterministic. `ingest` returns its persist
    /// `Task`, so `collectionStartsWhenFlagAndOptInEnabled` awaits the work
    /// instead of watching for its side effects; that test was the one that
    /// actually flaked, twice — a 1s budget reddened #115, and 5s wasn't enough
    /// either when it needed 33.6s under CI contention on 2026-08-29.
    ///
    /// The timeout only bounds the *failing* path — the loop returns the moment
    /// the condition is true — so this is sized generously for an in-process
    /// observation hop with no I/O, not tuned.
    private func waitUntil(
        timeoutSeconds: TimeInterval = 10,
        intervalNanoseconds: UInt64 = 10_000_000,
        condition: @escaping () -> Bool
    ) async {
        let start = Date()
        let deadline = start.addingTimeInterval(timeoutSeconds)
        while condition() == false {
            if Date() >= deadline {
                let waited = String(format: "%.2f", Date().timeIntervalSince(start))
                Issue.record("Condition was not met before timeout (waited \(waited)s of \(timeoutSeconds)s)")
                return
            }
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }
    }
}
