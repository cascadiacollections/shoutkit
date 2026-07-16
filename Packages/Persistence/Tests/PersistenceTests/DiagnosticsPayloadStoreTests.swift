import Foundation
import Testing

@testable import Persistence

struct DiagnosticsPayloadStoreTests {
    @Test func persistsMetricAndDiagnosticPayloads() throws {
        let store = try DiagnosticsPayloadStore(path: ":memory:")

        store.persist(
            metricPayloads: [Data("metric-a".utf8), Data("metric-b".utf8)],
            diagnosticPayloads: [Data("diag-a".utf8)],
            receivedAt: Date()
        )

        #expect(try store.payloadCount() == 3)
    }

    @Test func extractsLaunchAndNetworkSummariesFromStoredMetricPayloads() throws {
        let store = try DiagnosticsPayloadStore(path: ":memory:")
        let payload = try JSONSerialization.data(withJSONObject: [
            "appLaunchMetrics": [
                "histogrammedTimeToFirstDraw": [
                    "bucketStartTimes": [0, 100, 200],
                    "bucketEndTimes": [100, 200, 300],
                    "bucketCounts": [1, 2, 1],
                    "unit": "ms"
                ],
                "histogrammedApplicationResumeTime": [
                    "bucketStartTimes": [0, 100],
                    "bucketEndTimes": [100, 200],
                    "bucketCounts": [1, 1],
                    "unit": "ms"
                ]
            ],
            "networkTransactionMetrics": [[
                "domain": "api.example.com",
                "networkProtocolName": "https",
                "count": 3,
                "dns": ["duration": ["value": 0.012, "unit": "s"]],
                "connect": ["duration": ["value": 0.034, "unit": "s"]],
                "tls": ["duration": ["value": 0.056, "unit": "s"]],
                "request": ["duration": ["value": 0.007, "unit": "s"]],
                "response": ["duration": ["value": 0.089, "unit": "s"]],
                "cumulative": ["duration": ["value": 0.120, "unit": "s"]]
            ]]
        ])

        store.persist(metricPayloads: [payload], diagnosticPayloads: [], receivedAt: Date())

        let summaries = try store.metricPayloadSummaries(limit: 5)

        #expect(summaries.count == 1)
        #expect(summaries.first?.launch?.meanTimeToFirstDrawMilliseconds == 150)
        #expect(summaries.first?.launch?.timeToFirstDrawSampleCount == 4)
        #expect(summaries.first?.launch?.meanResumeTimeMilliseconds == 100)
        #expect(summaries.first?.networkTransactions == [
            DiagnosticsNetworkTransactionSummary(
                host: "api.example.com",
                requestCount: 3,
                networkProtocol: "https",
                averageDNSMilliseconds: 12,
                averageConnectMilliseconds: 34,
                averageTLSMilliseconds: 56,
                averageRequestMilliseconds: 7,
                averageResponseMilliseconds: 89,
                averageTotalMilliseconds: 120
            )
        ])
    }

    @Test func ignoresUnparseableMetricPayloadsWhenSummarizing() throws {
        let store = try DiagnosticsPayloadStore(path: ":memory:")

        store.persist(metricPayloads: [Data("not-json".utf8)], diagnosticPayloads: [], receivedAt: Date())

        #expect(try store.metricPayloadSummaries(limit: 5).isEmpty)
    }
}
