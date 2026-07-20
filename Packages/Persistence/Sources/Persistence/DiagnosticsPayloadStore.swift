import Foundation
import GRDB

public protocol DiagnosticsPayloadPersisting: AnyObject {
    func persist(metricPayloads: [Data], diagnosticPayloads: [Data], receivedAt: Date) throws
    func metricPayloadSummaries(limit: Int) throws -> [DiagnosticsMetricPayloadSummary]
}

/// File-scope (not nested in `Record`) to satisfy SwiftLint's one-level
/// type-nesting limit; the raw values are what lands in the `kind` column.
private enum DiagnosticsPayloadKind: String, Codable {
    case metric
    case diagnostic
}

public final class DiagnosticsPayloadStore: DiagnosticsPayloadPersisting {
    private struct Record: Codable, FetchableRecord, PersistableRecord {
        static let databaseTableName = "diagnostic_payloads"

        var id: Int64?
        var kind: DiagnosticsPayloadKind
        var payload: Data
        var receivedAt: Date
    }

    private let dbQueue: DatabaseQueue
    private static let payloadRetentionDays = 30

    public init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrate()
    }

    public convenience init() throws {
        try self.init(path: Self.defaultDatabasePath().path)
    }

    public func persist(metricPayloads: [Data], diagnosticPayloads: [Data], receivedAt: Date) throws {
        guard !metricPayloads.isEmpty || !diagnosticPayloads.isEmpty else { return }
        try dbQueue.write { database in
            for payload in metricPayloads {
                try Record(id: nil, kind: .metric, payload: payload, receivedAt: receivedAt).insert(database)
            }
            for payload in diagnosticPayloads {
                try Record(id: nil, kind: .diagnostic, payload: payload, receivedAt: receivedAt).insert(database)
            }

            let cutoff = Calendar.current.date(byAdding: .day, value: -Self.payloadRetentionDays, to: receivedAt)
                ?? receivedAt
            _ = try Record
                .filter(Column("receivedAt") < cutoff)
                .deleteAll(database)
        }
    }

    public func metricPayloadSummaries(limit: Int) throws -> [DiagnosticsMetricPayloadSummary] {
        guard limit > 0 else { return [] }
        return try dbQueue.read { database in
            let records = try Record
                .filter(Column("kind") == DiagnosticsPayloadKind.metric.rawValue)
                .order(Column("receivedAt").desc)
                .order(Column("id").desc)
                .limit(limit)
                .fetchAll(database)

            return records.compactMap {
                DiagnosticsMetricSummaryExtractor.summary(from: $0.payload, receivedAt: $0.receivedAt)
            }
        }
    }

    func payloadCount() throws -> Int {
        try dbQueue.read { database in
            try Record.fetchCount(database)
        }
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createDiagnosticsPayloads") { database in
            try database.create(table: Record.databaseTableName) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("kind", .text).notNull()
                table.column("payload", .blob).notNull()
                table.column("receivedAt", .datetime).notNull()
            }
        }
        try migrator.migrate(dbQueue)
    }

    private static func defaultDatabasePath(fileManager: FileManager = .default) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = appSupport.appendingPathComponent("ShoutKit", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("diagnostics.sqlite")
    }
}

public final class InMemoryDiagnosticsPayloadStore: DiagnosticsPayloadPersisting {
    private(set) public var metricPayloads: [Data] = []
    private(set) public var diagnosticPayloads: [Data] = []
    private var metricRecords: [(payload: Data, receivedAt: Date)] = []
    private var diagnosticRecords: [(payload: Data, receivedAt: Date)] = []

    public init() {}

    public func persist(metricPayloads: [Data], diagnosticPayloads: [Data], receivedAt: Date) throws {
        self.metricRecords.append(contentsOf: metricPayloads.map { ($0, receivedAt) })
        self.diagnosticRecords.append(contentsOf: diagnosticPayloads.map { ($0, receivedAt) })
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: receivedAt) ?? receivedAt
        self.metricRecords.removeAll { $0.receivedAt < cutoff }
        self.diagnosticRecords.removeAll { $0.receivedAt < cutoff }
        self.metricPayloads = self.metricRecords.map(\.payload)
        self.diagnosticPayloads = self.diagnosticRecords.map(\.payload)
    }

    public func metricPayloadSummaries(limit: Int) throws -> [DiagnosticsMetricPayloadSummary] {
        guard limit > 0 else { return [] }
        return metricRecords
            .suffix(limit)
            .reversed()
            .compactMap { record in
                DiagnosticsMetricSummaryExtractor.summary(from: record.payload, receivedAt: record.receivedAt)
            }
    }
}
