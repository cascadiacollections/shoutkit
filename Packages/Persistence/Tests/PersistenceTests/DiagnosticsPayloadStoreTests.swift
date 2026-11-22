import Foundation
@testable import Persistence
import Testing

struct DiagnosticsPayloadStoreTests {
    @Test func `persists metric and diagnostic payloads`() throws {
        let store = try DiagnosticsPayloadStore.inMemory()

        try store.persist(
            metricPayloads: [Data("metric-a".utf8), Data("metric-b".utf8)],
            diagnosticPayloads: [Data("diag-a".utf8)],
            receivedAt: Date(),
        )

        #expect(try store.payloadCount() == 3)
    }

    @Test func `extracts launch summaries from stored metric payloads`() throws {
        let store = try DiagnosticsPayloadStore.inMemory()
        let payload = try JSONSerialization.data(withJSONObject: [
            "applicationLaunchMetrics": [
                "histogrammedTimeToFirstDraw": [
                    "histogramValue": [
                        "0": "1810 ms",
                        "1": "1210 ms",
                    ],
                ],
                "histogrammedApplicationResumeTime": [
                    "histogramValue": [
                        "0": "620 ms",
                        "1": "1180 ms",
                    ],
                ],
            ],
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

    @Test func `ignores unparseable metric payloads when summarizing`() throws {
        let store = try DiagnosticsPayloadStore.inMemory()

        try store.persist(metricPayloads: [Data("not-json".utf8)], diagnosticPayloads: [], receivedAt: Date())

        #expect(try store.metricPayloadSummaries(limit: 5).isEmpty)
    }

    @Test func `prunes payloads outside retention window`() throws {
        let store = try DiagnosticsPayloadStore.inMemory()
        let oldDate = try #require(Calendar.current.date(byAdding: .day, value: -40, to: Date()))
        let currentDate = Date()

        try store.persist(
            metricPayloads: [Data("old".utf8)],
            diagnosticPayloads: [Data("old-diag".utf8)],
            receivedAt: oldDate,
        )
        try store.persist(
            metricPayloads: [Data("new".utf8)],
            diagnosticPayloads: [],
            receivedAt: currentDate,
        )

        #expect(try store.payloadCount() == 1)
    }

    @Test func `parses histogram duration strings across supported formats`() throws {
        let store = try DiagnosticsPayloadStore.inMemory()
        let payload = try JSONSerialization.data(withJSONObject: [
            "applicationLaunchMetrics": [
                "histogrammedTimeToFirstDraw": [
                    "histogramValue": [
                        "0": "+1.5ms",
                        "1": "2.5 ms",
                    ],
                ],
                "histogrammedApplicationResumeTime": [
                    "histogramValue": [
                        "0": "-2.3 s",
                    ],
                ],
            ],
        ])

        try store.persist(metricPayloads: [payload], diagnosticPayloads: [], receivedAt: Date())

        let summary = try #require(store.metricPayloadSummaries(limit: 1).first)
        #expect(summary.launch?.meanTimeToFirstDrawMilliseconds == 2)
        #expect(summary.launch?.meanResumeTimeMilliseconds == -2300)
    }

    @Test func `ignores malformed histogram duration strings`() throws {
        let store = try DiagnosticsPayloadStore.inMemory()
        let payload = try JSONSerialization.data(withJSONObject: [
            "applicationLaunchMetrics": [
                "histogrammedTimeToFirstDraw": [
                    "histogramValue": [
                        "0": "1.2-3.4ms",
                    ],
                ],
            ],
        ])

        try store.persist(metricPayloads: [payload], diagnosticPayloads: [], receivedAt: Date())

        #expect(try store.metricPayloadSummaries(limit: 1).isEmpty)
    }

    @Test func `summarizes the newest metric payloads first`() throws {
        let store = try DiagnosticsPayloadStore.inMemory()
        let now = Date()

        try store.persist(
            metricPayloads: [Self.launchPayload(milliseconds: 100)],
            diagnosticPayloads: [],
            receivedAt: now.addingTimeInterval(-60),
        )
        try store.persist(
            metricPayloads: [Self.launchPayload(milliseconds: 200), Self.launchPayload(milliseconds: 300)],
            diagnosticPayloads: [Self.launchPayload(milliseconds: 999)],
            receivedAt: now,
        )

        let all = try store.metricPayloadSummaries(limit: 5)
        #expect(all.map(\.launch?.meanTimeToFirstDrawMilliseconds) == [300, 200, 100])
        let limited = try store.metricPayloadSummaries(limit: 2)
        #expect(limited.map(\.launch?.meanTimeToFirstDrawMilliseconds) == [300, 200])
    }

    @Test func `keeps payloads across a reopen of the same file`() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagnosticsPayloadStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("diagnostics.store")

        try DiagnosticsPayloadStore(url: url).persist(
            metricPayloads: [Data("metric".utf8)],
            diagnosticPayloads: [Data("diag".utf8)],
            receivedAt: Date(),
        )

        #expect(try DiagnosticsPayloadStore(url: url).payloadCount() == 2)
    }

    @Test func `removes the database the GRDB store left behind`() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagnosticsPayloadStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let legacy = ["diagnostics.sqlite", "diagnostics.sqlite-wal"].map { folder.appendingPathComponent($0) }
        let unrelated = folder.appendingPathComponent("diagnostics.store")
        for url in legacy + [unrelated] {
            try Data("x".utf8).write(to: url)
        }

        DiagnosticsPayloadStore.removeLegacyDatabase(in: folder)

        for url in legacy {
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    private static func launchPayload(milliseconds: Int) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "applicationLaunchMetrics": [
                "histogrammedTimeToFirstDraw": [
                    "histogramValue": ["0": "\(milliseconds) ms"],
                ],
            ],
        ])
    }
}
