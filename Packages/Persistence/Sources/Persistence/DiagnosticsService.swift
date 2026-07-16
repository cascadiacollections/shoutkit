import FeatureFlags
import Foundation
#if canImport(OSLog)
import OSLog
#endif

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
    #if canImport(OSLog)
    private static let logger = Logger(subsystem: "ShoutKit.Persistence", category: "DiagnosticsService")
    #endif

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
        let receivedAt = Date()
        payloadStore.persist(
            metricPayloads: metricPayloads,
            diagnosticPayloads: diagnosticPayloads,
            receivedAt: receivedAt
        )
        logMetricPayloadSummaries(limit: metricPayloads.count, receivedAt: receivedAt)
    }

    var shouldCollectDiagnostics: Bool {
        featureFlags.isEnabled(Self.diagnosticsFeature) && settings.isDiagnosticsSharingEnabled
    }

    var subscribedForCollection: Bool { isSubscribed }

    private func logMetricPayloadSummaries(limit: Int, receivedAt: Date) {
        guard limit > 0 else { return }
        do {
            let summaries = try payloadStore.metricPayloadSummaries(limit: limit)
            for summary in summaries {
                if let launch = summary.launch {
                    Self.log(
                        """
                        MetricKit launch receivedAt=\(receivedAt.formatted(.iso8601)) \
                        timeToFirstDrawMeanMs=\(Self.describe(launch.meanTimeToFirstDrawMilliseconds)) \
                        timeToFirstDrawSamples=\(launch.timeToFirstDrawSampleCount) \
                        resumeMeanMs=\(Self.describe(launch.meanResumeTimeMilliseconds)) \
                        resumeSamples=\(launch.resumeSampleCount)
                        """
                    )
                }
                for transaction in summary.networkTransactions {
                    Self.log(transaction.logMessage)
                }
            }
        } catch {
            Self.log("Failed to summarize persisted MetricKit payloads: \(error)")
        }
    }

    private static func describe(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.2f", value)
    }

    private static func log(_ message: String) {
        #if canImport(OSLog)
        logger.notice("\(message, privacy: .public)")
        #else
        print(message)
        #endif
    }

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
