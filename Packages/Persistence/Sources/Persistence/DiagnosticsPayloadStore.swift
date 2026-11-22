import Foundation
import SwiftData

public protocol DiagnosticsPayloadPersisting: AnyObject, Sendable {
    func persist(metricPayloads: [Data], diagnosticPayloads: [Data], receivedAt: Date) throws
    func metricPayloadSummaries(limit: Int) throws -> [DiagnosticsMetricPayloadSummary]
}

/// The raw values are what lands in `DiagnosticsPayloadRecord.kindRawValue`.
private enum DiagnosticsPayloadKind: String {
    case metric
    case diagnostic
}

/// A failure raised by ``DiagnosticsPayloadStore`` itself.
///
/// Public because it escapes through public `throws` signatures
/// (``DiagnosticsPayloadStore/persist(metricPayloads:diagnosticPayloads:receivedAt:)``);
/// a caller cannot catch by type an error it cannot name. Failures originating
/// in SwiftData are propagated unwrapped and are not part of this enum.
/// No `LocalizedError` conformance, unlike `RadioDirectoryError` and
/// `PlaybackError`: this package declares no resources, so it has no string
/// catalog to localize against, and nothing here is shown to a listener —
/// diagnostics failures are swallowed into `LibraryStore.lastErrorMessage` or
/// logged. Adding one would mean adding a catalog to the target first.
public enum DiagnosticsPayloadStoreError: Error, Equatable, Sendable {
    /// The retention cutoff could not be derived from the supplied date —
    /// `Calendar.date(byAdding:value:to:)` returned `nil`.
    case invalidRetentionCutoffDate
}

private let diagnosticsPayloadRetentionDays = 30

/// One stored MetricKit payload. It lives in its own store file, apart from
/// ``ShoutKitModelContainer``'s schema, so a change here can never stop the
/// favorites store from opening (DECISIONS.md, 2026-11-22).
@Model
final class DiagnosticsPayloadRecord {
    /// A ``DiagnosticsPayloadKind`` raw value. Stored as a plain `String` so
    /// `#Predicate` can compare it.
    var kindRawValue: String
    var payload: Data
    var receivedAt: Date
    /// Position within the `persist` call that wrote this row. Payloads from one
    /// call share a `receivedAt`, so this is what orders them.
    var batchIndex: Int

    init(kindRawValue: String, payload: Data, receivedAt: Date, batchIndex: Int) {
        self.kindRawValue = kindRawValue
        self.payload = payload
        self.receivedAt = receivedAt
        self.batchIndex = batchIndex
    }
}

/// SwiftData-backed store for MetricKit payloads, with 30-day retention.
///
/// Each call works in a `ModelContext` of its own, so the store can be used
/// from any isolation; `DiagnosticsService` serializes its calls on an actor.
public final class DiagnosticsPayloadStore: DiagnosticsPayloadPersisting {
    private static let schema = Schema([DiagnosticsPayloadRecord.self])

    private let container: ModelContainer

    /// Opens, or creates, the store file at `url`.
    public convenience init(url: URL) throws {
        try self.init(
            configuration: ModelConfiguration(
                "ShoutKitDiagnostics",
                schema: Self.schema,
                url: url,
                cloudKitDatabase: .none,
            ),
        )
    }

    /// Opens the store at its default location in Application Support.
    public convenience init() throws {
        let folder = try Self.defaultFolder()
        Self.removeLegacyDatabase(in: folder)
        try self.init(url: folder.appendingPathComponent("diagnostics.store"))
    }

    init(configuration: ModelConfiguration) throws {
        container = try ModelContainer(for: Self.schema, configurations: [configuration])
    }

    /// A store that keeps nothing on disk, for tests. The unique name keeps two
    /// of them from sharing rows.
    static func inMemory() throws -> DiagnosticsPayloadStore {
        try DiagnosticsPayloadStore(
            configuration: ModelConfiguration(
                "ShoutKitDiagnosticsInMemory-\(UUID().uuidString)",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none,
            ),
        )
    }

    public func persist(metricPayloads: [Data], diagnosticPayloads: [Data], receivedAt: Date) throws {
        guard !metricPayloads.isEmpty || !diagnosticPayloads.isEmpty else { return }
        guard let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -diagnosticsPayloadRetentionDays,
            to: receivedAt,
        ) else {
            throw DiagnosticsPayloadStoreError.invalidRetentionCutoffDate
        }
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let kinded = metricPayloads.map { (DiagnosticsPayloadKind.metric, $0) }
            + diagnosticPayloads.map { (DiagnosticsPayloadKind.diagnostic, $0) }
        for (index, entry) in kinded.enumerated() {
            context.insert(
                DiagnosticsPayloadRecord(
                    kindRawValue: entry.0.rawValue,
                    payload: entry.1,
                    receivedAt: receivedAt,
                    batchIndex: index,
                ),
            )
        }

        // Fetch-and-delete rather than `delete(model:where:)`: the table holds a
        // few dozen rows, and this path behaves the same on an in-memory store.
        let expired = FetchDescriptor<DiagnosticsPayloadRecord>(
            predicate: #Predicate<DiagnosticsPayloadRecord> { $0.receivedAt < cutoff },
        )
        for record in try context.fetch(expired) {
            context.delete(record)
        }
        try context.save()
    }

    public func metricPayloadSummaries(limit: Int) throws -> [DiagnosticsMetricPayloadSummary] {
        guard limit > 0 else { return [] }
        let metricKind = DiagnosticsPayloadKind.metric.rawValue
        var descriptor = FetchDescriptor<DiagnosticsPayloadRecord>(
            predicate: #Predicate<DiagnosticsPayloadRecord> { $0.kindRawValue == metricKind },
            sortBy: [
                SortDescriptor(\.receivedAt, order: .reverse),
                SortDescriptor(\.batchIndex, order: .reverse),
            ],
        )
        descriptor.fetchLimit = limit

        return try ModelContext(container).fetch(descriptor).compactMap {
            DiagnosticsMetricSummaryExtractor.summary(from: $0.payload, receivedAt: $0.receivedAt)
        }
    }

    func payloadCount() throws -> Int {
        try ModelContext(container).fetchCount(FetchDescriptor<DiagnosticsPayloadRecord>())
    }

    private static func defaultFolder(fileManager: FileManager = .default) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true,
        )
        let folder = appSupport.appendingPathComponent("ShoutKit", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Deletes the GRDB database this store replaced, and its journal files.
    /// Its rows are not migrated: they are developer diagnostics that expire
    /// after 30 days anyway.
    static func removeLegacyDatabase(in folder: URL, fileManager: FileManager = .default) {
        for suffix in ["", "-journal", "-wal", "-shm"] {
            try? fileManager.removeItem(at: folder.appendingPathComponent("diagnostics.sqlite" + suffix))
        }
    }
}

public final class InMemoryDiagnosticsPayloadStore: DiagnosticsPayloadPersisting, @unchecked Sendable {
    public private(set) var metricPayloads: [Data] = []
    public private(set) var diagnosticPayloads: [Data] = []
    private var metricRecords: [(payload: Data, receivedAt: Date)] = []
    private var diagnosticRecords: [(payload: Data, receivedAt: Date)] = []

    public init() {}

    public func persist(metricPayloads: [Data], diagnosticPayloads: [Data], receivedAt: Date) throws {
        guard let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -diagnosticsPayloadRetentionDays,
            to: receivedAt,
        ) else {
            throw DiagnosticsPayloadStoreError.invalidRetentionCutoffDate
        }
        self.metricRecords.append(contentsOf: metricPayloads.map { ($0, receivedAt) })
        self.diagnosticRecords.append(contentsOf: diagnosticPayloads.map { ($0, receivedAt) })
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
