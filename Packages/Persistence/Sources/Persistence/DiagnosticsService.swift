import FeatureFlags
import Foundation
import Observation
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
    private nonisolated(unsafe) static let logger = Logger(
        subsystem: "ShoutKit.Persistence",
        category: "DiagnosticsService"
    )
    #endif

    private let featureFlags: any FeatureFlagProviding
    private let settings: SettingsStore
    private let subscribe: SubscriptionHandler
    private let unsubscribe: SubscriptionHandler
    private let ingestWorker: DiagnosticsIngestWorker
    private var isSubscribed = false
    private var observationTask: Task<Void, Never>?

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
        self.subscribe = subscribe ?? DiagnosticsService.defaultSubscribe
        self.unsubscribe = unsubscribe ?? DiagnosticsService.defaultUnsubscribe
        self.ingestWorker = DiagnosticsIngestWorker(payloadStore: payloadStore)
        super.init()
        observeCollectionEligibility()
        refreshSubscription()
    }

    deinit {
        observationTask?.cancel()
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
        let metricPayloadsToPersist = metricPayloads
        let diagnosticPayloadsToPersist = diagnosticPayloads
        let worker = ingestWorker
        Task(priority: .utility) {
            await worker.persistAndLogSummaries(
                metricPayloads: metricPayloadsToPersist,
                diagnosticPayloads: diagnosticPayloadsToPersist,
                receivedAt: receivedAt
            )
        }
    }

    var shouldCollectDiagnostics: Bool {
        featureFlags.isEnabled(Self.diagnosticsFeature) && settings.isDiagnosticsSharingEnabled
    }

    var subscribedForCollection: Bool { isSubscribed }

    private func observeCollectionEligibility() {
        observationTask = Task { @MainActor [weak self] in
            let changes = Observations { [weak self] in
                guard let self else { return (false, false) }
                return (
                    self.settings.isDiagnosticsSharingEnabled,
                    self.featureFlags.isEnabled(Self.diagnosticsFeature)
                )
            }

            for await _ in changes {
                if Task.isCancelled { return }
                guard let self else { return }
                self.refreshSubscription()
            }
        }
    }

    private nonisolated static func describe(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.2f", value)
    }

    private nonisolated static func log(_ message: String) {
        #if canImport(OSLog)
        logger.notice("\(message, privacy: .public)")
        #else
        print(message)
        #endif
    }

    private nonisolated static func logMetricPayloadSummaries(
        _ summaries: [DiagnosticsMetricPayloadSummary],
        receivedAt: Date
    ) {
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
    }

    private static func defaultSubscribe(_ service: DiagnosticsService) {
        #if canImport(MetricKit) && os(iOS)
        MXMetricManager.shared.add(service)
        #else
        _ = service
        #endif
    }

    private actor DiagnosticsIngestWorker {
        private let payloadStore: any DiagnosticsPayloadPersisting

        init(payloadStore: any DiagnosticsPayloadPersisting) {
            self.payloadStore = payloadStore
        }

        func persistAndLogSummaries(metricPayloads: [Data], diagnosticPayloads: [Data], receivedAt: Date) {
            do {
                try payloadStore.persist(
                    metricPayloads: metricPayloads,
                    diagnosticPayloads: diagnosticPayloads,
                    receivedAt: receivedAt
                )
                let summaries = metricPayloads.compactMap {
                    DiagnosticsMetricSummaryExtractor.summary(from: $0, receivedAt: receivedAt)
                }
                DiagnosticsService.logMetricPayloadSummaries(summaries, receivedAt: receivedAt)
            } catch {
                DiagnosticsService.log("Failed to persist MetricKit payloads: \(error)")
            }
        }
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
