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
    private final class FeatureFlagsStub: FeatureFlagProviding {
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

        service.ingest(metricPayloads: [Data("metric".utf8)], diagnosticPayloads: [Data("diag".utf8)])

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

        service.ingest(metricPayloads: [Data("metric".utf8)], diagnosticPayloads: [Data("diag".utf8)])

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

        service.ingest(metricPayloads: [Data("metric".utf8)], diagnosticPayloads: [Data("diag".utf8)])

        #expect(subscribeCalls == 1)
        await waitUntil {
            payloadStore.metricPayloads.count == 1 && payloadStore.diagnosticPayloads.count == 1
        }
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

    private func waitUntil(
        timeoutSeconds: TimeInterval = 1,
        intervalNanoseconds: UInt64 = 10_000_000,
        condition: @MainActor @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while await condition() == false {
            if Date() >= deadline {
                Issue.record("Condition was not met before timeout")
                return
            }
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }
    }
}
