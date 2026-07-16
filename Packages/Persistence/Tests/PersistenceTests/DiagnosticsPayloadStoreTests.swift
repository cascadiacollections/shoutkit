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
        // The seconds→milliseconds conversion goes through Double arithmetic
        // (0.034 * 1000 == 33.999…), so compare timings with a tolerance
        // instead of exact struct equality.
        let transaction = try #require(summaries.first?.networkTransactions.first)
        #expect(summaries.first?.networkTransactions.count == 1)
        #expect(transaction.host == "api.example.com")
        #expect(transaction.requestCount == 3)
        #expect(transaction.networkProtocol == "https")
        expectApproximately(transaction.averageDNSMilliseconds, 12)
        expectApproximately(transaction.averageConnectMilliseconds, 34)
        expectApproximately(transaction.averageTLSMilliseconds, 56)
        expectApproximately(transaction.averageRequestMilliseconds, 7)
        expectApproximately(transaction.averageResponseMilliseconds, 89)
        expectApproximately(transaction.averageTotalMilliseconds, 120)
    }

    private func expectApproximately(
        _ value: Double?,
        _ expected: Double,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let value else {
            Issue.record("expected \(expected), got nil", sourceLocation: sourceLocation)
            return
        }
        #expect(abs(value - expected) < 0.001, sourceLocation: sourceLocation)
    }

    @Test func ignoresUnparseableMetricPayloadsWhenSummarizing() throws {
        let store = try DiagnosticsPayloadStore(path: ":memory:")

        store.persist(metricPayloads: [Data("not-json".utf8)], diagnosticPayloads: [], receivedAt: Date())

        #expect(try store.metricPayloadSummaries(limit: 5).isEmpty)
    }
}
