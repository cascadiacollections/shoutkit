import FeatureFlags
import Foundation

#if canImport(MetricKit)
import MetricKit
#endif

@MainActor
public protocol DiagnosticsServicing: AnyObject {
    func refreshSubscription()
}

@MainActor
public final class DiagnosticsService: NSObject, DiagnosticsServicing {
    public typealias SubscriptionHandler = @MainActor (DiagnosticsService) -> Void

    private static let diagnosticsFeature: Feature = {
        guard let feature = FeatureCatalog.all.first(where: { $0.key == "diagnostics" }) else {
            preconditionFailure("Missing diagnostics feature in FeatureCatalog")
        }
        return feature
    }()

    private let featureFlags: any FeatureFlagProviding
    private let settings: SettingsStore
    private let payloadStore: any DiagnosticsPayloadPersisting
    private let subscribe: SubscriptionHandler
    private let unsubscribe: SubscriptionHandler
    private var isSubscribed = false

    public init(
        featureFlags: any FeatureFlagProviding,
        settings: SettingsStore,
        payloadStore: any DiagnosticsPayloadPersisting,
        subscribe: @escaping SubscriptionHandler = Self.defaultSubscribe,
        unsubscribe: @escaping SubscriptionHandler = Self.defaultUnsubscribe
    ) {
        self.featureFlags = featureFlags
        self.settings = settings
        self.payloadStore = payloadStore
        self.subscribe = subscribe
        self.unsubscribe = unsubscribe
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
        #if canImport(MetricKit)
        MXMetricManager.shared.add(service)
        #else
        _ = service
        #endif
    }

    private static func defaultUnsubscribe(_ service: DiagnosticsService) {
        #if canImport(MetricKit)
        MXMetricManager.shared.remove(service)
        #else
        _ = service
        #endif
    }
}

#if canImport(MetricKit)
@MainActor
extension DiagnosticsService: MXMetricManagerSubscriber {
    public nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        let jsonPayloads = payloads.compactMap { $0.jsonRepresentation() }
        Task { @MainActor in
            ingest(metricPayloads: jsonPayloads, diagnosticPayloads: [])
        }
    }

    public nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let jsonPayloads = payloads.compactMap { $0.jsonRepresentation() }
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
