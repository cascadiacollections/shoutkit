import FeatureFlags
import Foundation

// MetricKit's metric payloads (MXMetricPayload) are unavailable on macOS, so
// gate on os(iOS) too — the package's tests build for the mac host.
#if canImport(MetricKit) && os(iOS)
import MetricKit
#endif

@MainActor
public protocol DiagnosticsServicing: AnyObject {
    func refreshSubscription()
}

@MainActor
public final class DiagnosticsService: NSObject, DiagnosticsServicing {
    public typealias SubscriptionHandler = @MainActor (DiagnosticsService) -> Void

    private static let diagnosticsFeature = FeatureCatalog.diagnostics

    private let featureFlags: any FeatureFlagProviding
    private let settings: SettingsStore
    private let payloadStore: any DiagnosticsPayloadPersisting
    private let subscribe: SubscriptionHandler
    private let unsubscribe: SubscriptionHandler
    private var isSubscribed = false

    /// Passing nil for `subscribe`/`unsubscribe` uses the real MXMetricManager
    /// handlers; tests inject stubs. (nil-defaults rather than direct default
    /// arguments because a public init can't reference the private static
    /// handlers, nor `Self`, in a default argument expression.)
    public init(
        featureFlags: any FeatureFlagProviding,
        settings: SettingsStore,
        payloadStore: any DiagnosticsPayloadPersisting,
        subscribe: SubscriptionHandler? = nil,
        unsubscribe: SubscriptionHandler? = nil
    ) {
        self.featureFlags = featureFlags
        self.settings = settings
        self.payloadStore = payloadStore
        self.subscribe = subscribe ?? DiagnosticsService.defaultSubscribe
        self.unsubscribe = unsubscribe ?? DiagnosticsService.defaultUnsubscribe
        super.init()
        refreshSubscription()
    }

    public func refreshSubscription() {
        let shouldCollect = shouldCollectDiagnostics
        if shouldCollect, isSubscribed == false {
            subscribe(self)
            isSubscribed = true
        } else if shouldCollect == false, isSubscribed {
            unsubscribe(self)
            isSubscribed = false
        }
    }

    func ingest(metricPayloads: [Data], diagnosticPayloads: [Data]) {
        guard shouldCollectDiagnostics else { return }
        payloadStore.persist(metricPayloads: metricPayloads, diagnosticPayloads: diagnosticPayloads, receivedAt: Date())
    }

    var shouldCollectDiagnostics: Bool {
        featureFlags.isEnabled(Self.diagnosticsFeature) && settings.isDiagnosticsSharingEnabled
    }

    var subscribedForCollection: Bool { isSubscribed }

    private static func defaultSubscribe(_ service: DiagnosticsService) {
        #if canImport(MetricKit) && os(iOS)
        MXMetricManager.shared.add(service)
        #else
        _ = service
        #endif
    }

    private static func defaultUnsubscribe(_ service: DiagnosticsService) {
        #if canImport(MetricKit) && os(iOS)
        MXMetricManager.shared.remove(service)
        #else
        _ = service
        #endif
    }
}

#if canImport(MetricKit) && os(iOS)
@MainActor
extension DiagnosticsService: MXMetricManagerSubscriber {
    public nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        let jsonPayloads = payloads.map { $0.jsonRepresentation() }
        Task { @MainActor in
            ingest(metricPayloads: jsonPayloads, diagnosticPayloads: [])
        }
    }

    public nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let jsonPayloads = payloads.map { $0.jsonRepresentation() }
        Task { @MainActor in
            ingest(metricPayloads: [], diagnosticPayloads: jsonPayloads)
        }
    }
}
#endif

@MainActor
public final class NoopDiagnosticsService: DiagnosticsServicing {
    public init() {}
    public func refreshSubscription() {}
}
