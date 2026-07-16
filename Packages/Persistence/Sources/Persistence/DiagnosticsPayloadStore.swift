import Foundation
import GRDB
#if canImport(OSLog)
import OSLog
#endif

public protocol DiagnosticsPayloadPersisting: AnyObject {
    func persist(metricPayloads: [Data], diagnosticPayloads: [Data], receivedAt: Date)
}

/// File-scope (not nested in `Record`) to satisfy SwiftLint's one-level
/// type-nesting limit; the raw values are what lands in the `kind` column.
private enum DiagnosticsPayloadKind: String, Codable {
    case metric
    case diagnostic
}

public final class DiagnosticsPayloadStore: DiagnosticsPayloadPersisting {
    #if canImport(OSLog)
    private static let logger = Logger(subsystem: "com.cascadiacollections.shoutkit", category: "diagnostics")
    #endif

    private struct Record: Codable, FetchableRecord, PersistableRecord {
        static let databaseTableName = "diagnostic_payloads"

        var id: Int64?
        var kind: DiagnosticsPayloadKind
        var payload: Data
        var receivedAt: Date
    }

    private let dbQueue: DatabaseQueue

    public init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrate()
    }

    public convenience init() throws {
        try self.init(path: Self.defaultDatabasePath().path)
    }

    public func persist(metricPayloads: [Data], diagnosticPayloads: [Data], receivedAt: Date) {
        guard !metricPayloads.isEmpty || !diagnosticPayloads.isEmpty else { return }
        do {
            try dbQueue.write { database in
                for payload in metricPayloads {
                    try Record(id: nil, kind: .metric, payload: payload, receivedAt: receivedAt).insert(database)
                }
                for payload in diagnosticPayloads {
                    try Record(id: nil, kind: .diagnostic, payload: payload, receivedAt: receivedAt).insert(database)
                }
            }
        } catch {
            assertionFailure("Failed to persist diagnostics payloads: \(error)")
            #if canImport(OSLog)
            Self.logger.error("Failed to persist diagnostics payloads: \(String(describing: error), privacy: .private)")
            #else
            print("DiagnosticsPayloadStore persist error: \(error)")
            #endif
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

    public init() {}

    public func persist(metricPayloads: [Data], diagnosticPayloads: [Data], receivedAt _: Date) {
        self.metricPayloads.append(contentsOf: metricPayloads)
        self.diagnosticPayloads.append(contentsOf: diagnosticPayloads)
    }
}
