import Foundation
import os

/// The landing-surface content every discovery UX renders — popular stations and
/// the genre strip — captured together so a launch can paint from disk instead of
/// waiting on the directory, and can still paint at all with no usable connection.
///
/// Each half carries its own capture date because they're fetched independently
/// (genres are non-fatal to the landing surfaces, so a genres failure must not
/// backdate perfectly good station content, or vice versa).
public struct DirectoryDiscoverySnapshot: Codable, Equatable, Sendable {
    public struct TopStations: Codable, Equatable, Sendable {
        public let stations: [Station]
        /// The limit the fetch was issued with, retained so a snapshot captured
        /// at a larger limit can serve any smaller request — the same reasoning
        /// as ``CachingRadioDirectory``'s in-memory tier.
        public let limit: Int
        public let capturedAt: Date

        public init(stations: [Station], limit: Int, capturedAt: Date) {
            self.stations = stations
            self.limit = limit
            self.capturedAt = capturedAt
        }
    }

    public struct Genres: Codable, Equatable, Sendable {
        public let genres: [Genre]
        public let capturedAt: Date

        public init(genres: [Genre], capturedAt: Date) {
            self.genres = genres
            self.capturedAt = capturedAt
        }
    }

    public let topStations: TopStations?
    public let genres: Genres?
    /// Identifies the directory source and geo filter the content was fetched
    /// under, so a snapshot captured in one region isn't served after the filter
    /// changes (travel, or the geo-stations flag being toggled). `nil` when the
    /// source doesn't filter results.
    public let sourceIdentity: String?

    public init(
        topStations: TopStations? = nil,
        genres: Genres? = nil,
        sourceIdentity: String? = nil
    ) {
        self.topStations = topStations
        self.genres = genres
        self.sourceIdentity = sourceIdentity
    }

    /// The oldest capture date among the halves present — "what you're looking at
    /// is at least this old", which is the honest thing to show a reader.
    public var capturedAt: Date? {
        [topStations?.capturedAt, genres?.capturedAt].compactMap { $0 }.min()
    }

    /// Saved popular stations, empty when that half was never captured.
    public var savedStations: [Station] {
        topStations?.stations ?? []
    }

    /// Saved genre strip, empty when that half was never captured — genres are
    /// non-fatal to the landing surfaces, so this is allowed to be empty while
    /// stations are present.
    public var savedGenres: [Genre] {
        genres?.genres ?? []
    }

    public var isEmpty: Bool {
        topStations?.stations.isEmpty != false && genres?.genres.isEmpty != false
    }
}

/// A persisted snapshot plus whether it's still inside the caching directory's
/// stability window. A fresh snapshot is one a surface can render *and* stop
/// there: no directory request for that launch at all, so the list is byte-identical
/// to the previous launch instead of reshuffling as top-click rankings drift.
public struct DirectoryDiscoverySnapshotState: Equatable, Sendable {
    public let snapshot: DirectoryDiscoverySnapshot
    public let isFresh: Bool

    public init(snapshot: DirectoryDiscoverySnapshot, isFresh: Bool) {
        self.snapshot = snapshot
        self.isFresh = isFresh
    }
}

/// The persisted half of the directory cache, kept separate from
/// ``RadioDirectoryProviding`` so that boundary stays "fetch stations" and callers
/// that only want live data don't have to reason about cache policy.
public protocol DirectoryDiscoveryCaching: Sendable {
    /// The persisted landing content, or `nil` when nothing usable is stored (a
    /// first launch, or a snapshot captured under a different geo filter). Never
    /// touches the network.
    func discoverySnapshotState() async -> DirectoryDiscoverySnapshotState?

    /// Drops the short-lived in-memory windows so the next discovery read reaches
    /// the directory. Pull-to-refresh has to actually refresh.
    func invalidateMemoryCache() async
}

/// Persistence seam for ``DirectoryDiscoverySnapshot``. Both operations are
/// best-effort by contract: a missing, unreadable, or unwritable store degrades
/// to "no snapshot", never to an error the caller has to handle.
public protocol DirectorySnapshotStoring: Sendable {
    func load() async -> DirectoryDiscoverySnapshot?
    func save(_ snapshot: DirectoryDiscoverySnapshot) async
}

/// JSON-file snapshot store, written atomically into the app's Application
/// Support container (alongside the diagnostics database).
///
/// Application Support rather than Caches deliberately: the whole point of the
/// snapshot is that it's there on the launch where the network isn't, and the
/// system can evict a Caches directory at will. It's excluded from backup
/// instead, since it's regenerable from the directory.
public actor FileDirectorySnapshotStore: DirectorySnapshotStoring {
    /// Versioned in the file name: a future shape change simply doesn't find a
    /// file, so the content is refetched rather than mis-decoded.
    private static let fileName = "DiscoverySnapshot.v1.json"
    private static let directoryName = "ShoutKit"

    private static let logger = Logger(
        subsystem: "ShoutKit.RadioDirectory",
        category: "FileDirectorySnapshotStore"
    )

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Store rooted in the app's Application Support container. `nil` only when
    /// that container can't be resolved, in which case the app runs without a
    /// persisted snapshot rather than failing to launch.
    public static func applicationSupport(fileManager: FileManager = .default) -> FileDirectorySnapshotStore? {
        guard let container = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            logger.error("Application Support unavailable; running without a persisted directory snapshot")
            return nil
        }

        return FileDirectorySnapshotStore(
            fileURL: container
                .appendingPathComponent(directoryName, isDirectory: true)
                .appendingPathComponent(fileName, isDirectory: false),
            fileManager: fileManager
        )
    }

    public func load() async -> DirectoryDiscoverySnapshot? {
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try decoder.decode(DirectoryDiscoverySnapshot.self, from: data)
            // An empty snapshot is indistinguishable from having none, and
            // returning it would suppress the first real fetch.
            return snapshot.isEmpty ? nil : snapshot
        } catch {
            // The first launch (no file) is the common case here, and a
            // truncated or stale-shaped file is equally non-fatal: the caller
            // refetches either way.
            Self.logger.debug(
                "No usable directory snapshot on disk: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    public func save(_ snapshot: DirectoryDiscoverySnapshot) async {
        do {
            try createContainerDirectoryIfNeeded()
            try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
            excludeFromBackup()
        } catch {
            Self.logger.error(
                "Failed to persist directory snapshot: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// `withIntermediateDirectories: true` is a no-op when the directory already
    /// exists, so this needs no existence check (same as the diagnostics store).
    private func createContainerDirectoryIfNeeded() throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    /// Applied to the file, not its directory: the directory is shared with the
    /// diagnostics database, whose backup policy isn't this type's to decide.
    private func excludeFromBackup() {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var url = fileURL
        try? url.setResourceValues(resourceValues)
    }
}
