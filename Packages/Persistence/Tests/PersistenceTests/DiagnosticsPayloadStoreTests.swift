import Foundation
import Testing

@testable import Persistence

struct DiagnosticsPayloadStoreTests {
    @Test func persistsMetricAndDiagnosticPayloads() throws {
        let store = try DiagnosticsPayloadStore(path: ":memory:")

        try store.persist(
            metricPayloads: [Data("metric-a".utf8), Data("metric-b".utf8)],
            diagnosticPayloads: [Data("diag-a".utf8)],
            receivedAt: Date()
        )

        #expect(try store.payloadCount() == 3)
    }

    @Test func extractsLaunchSummariesFromStoredMetricPayloads() throws {
        let store = try DiagnosticsPayloadStore(path: ":memory:")
        let payload = try JSONSerialization.data(withJSONObject: [
            "applicationLaunchMetrics": [
                "histogrammedTimeToFirstDraw": [
                    "histogramValue": [
                        "0": "1810 ms",
                        "1": "1210 ms"
                    ]
                ],
                "histogrammedApplicationResumeTime": [
                    "histogramValue": [
                        "0": "620 ms",
                        "1": "1180 ms"
                    ]
                ]
            ]
        ])

        try store.persist(metricPayloads: [payload], diagnosticPayloads: [], receivedAt: Date())

        let summaries = try store.metricPayloadSummaries(limit: 5)

        #expect(summaries.count == 1)
        #expect(summaries.first?.launch?.meanTimeToFirstDrawMilliseconds == 1510)
        #expect(summaries.first?.launch?.timeToFirstDrawSampleCount == 2)
        #expect(summaries.first?.launch?.meanResumeTimeMilliseconds == 900)
        #expect(summaries.first?.launch?.resumeSampleCount == 2)
        #expect(summaries.first?.networkTransactions.isEmpty == true)
    }

    @Test func ignoresUnparseableMetricPayloadsWhenSummarizing() throws {
        let store = try DiagnosticsPayloadStore(path: ":memory:")

        try store.persist(metricPayloads: [Data("not-json".utf8)], diagnosticPayloads: [], receivedAt: Date())

        #expect(try store.metricPayloadSummaries(limit: 5).isEmpty)
    }

    @Test func prunesPayloadsOutsideRetentionWindow() throws {
        let store = try DiagnosticsPayloadStore(path: ":memory:")
        let oldDate = try #require(Calendar.current.date(byAdding: .day, value: -40, to: Date()))
        let currentDate = Date()

        try store.persist(
            metricPayloads: [Data("old".utf8)],
            diagnosticPayloads: [Data("old-diag".utf8)],
            receivedAt: oldDate
        )
        try store.persist(
            metricPayloads: [Data("new".utf8)],
            diagnosticPayloads: [],
            receivedAt: currentDate
        )

        #expect(try store.payloadCount() == 1)
    }

    @Test func parsesHistogramDurationStringsAcrossSupportedFormats() throws {
        let store = try DiagnosticsPayloadStore(path: ":memory:")
        let payload = try JSONSerialization.data(withJSONObject: [
            "applicationLaunchMetrics": [
                "histogrammedTimeToFirstDraw": [
                    "histogramValue": [
                        "0": "+1.5ms",
                        "1": "2.5 ms"
                    ]
                ],
                "histogrammedApplicationResumeTime": [
                    "histogramValue": [
                        "0": "-2.3 s"
                    ]
                ]
            ]
        ])

        try store.persist(metricPayloads: [payload], diagnosticPayloads: [], receivedAt: Date())

        let summary = try #require(store.metricPayloadSummaries(limit: 1).first)
        #expect(summary.launch?.meanTimeToFirstDrawMilliseconds == 2)
        #expect(summary.launch?.meanResumeTimeMilliseconds == -2300)
    }

    @Test func ignoresMalformedHistogramDurationStrings() throws {
        let store = try DiagnosticsPayloadStore(path: ":memory:")
        let payload = try JSONSerialization.data(withJSONObject: [
            "applicationLaunchMetrics": [
                "histogrammedTimeToFirstDraw": [
                    "histogramValue": [
                        "0": "1.2-3.4ms"
                    ]
                ]
            ]
        ])

        try store.persist(metricPayloads: [payload], diagnosticPayloads: [], receivedAt: Date())

        #expect(try store.metricPayloadSummaries(limit: 1).isEmpty)
    }
}
