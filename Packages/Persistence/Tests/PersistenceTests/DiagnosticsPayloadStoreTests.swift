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
}
