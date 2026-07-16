import Foundation
import GRDB
#if canImport(OSLog)
import OSLog
#endif

public protocol DiagnosticsPayloadPersisting: AnyObject {
    func persist(metricPayloads: [Data], diagnosticPayloads: [Data], receivedAt: Date)
}

public final class DiagnosticsPayloadStore: DiagnosticsPayloadPersisting {
    #if canImport(OSLog)
    private static let logger = Logger(subsystem: "com.cascadiacollections.shoutkit", category: "diagnostics")
    #endif

    private struct Record: Codable, FetchableRecord, PersistableRecord {
        static let databaseTableName = "diagnostic_payloads"

        enum Kind: String, Codable {
            case metric
            case diagnostic
        }

        var id: Int64?
        var kind: Kind
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
            try dbQueue.write { db in
                for payload in metricPayloads {
                    try Record(id: nil, kind: .metric, payload: payload, receivedAt: receivedAt).insert(db)
                }
                for payload in diagnosticPayloads {
                    try Record(id: nil, kind: .diagnostic, payload: payload, receivedAt: receivedAt).insert(db)
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
        try dbQueue.read { db in
            try Record.fetchCount(db)
        }
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createDiagnosticsPayloads") { db in
            try db.create(table: Record.databaseTableName) { table in
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
