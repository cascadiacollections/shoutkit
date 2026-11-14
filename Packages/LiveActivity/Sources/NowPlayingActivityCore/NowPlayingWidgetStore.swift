import Foundation

/// What the Quick Play widget shows while a station is playing or paused: the
/// station, the live track, and a token for the artwork staged next to it.
///
/// Written by the app (`NowPlayingWidgetCoordinator`), read by the widget
/// extension, which has no network access and no dependency graph of its own.
public struct NowPlayingWidgetSnapshot: Codable, Sendable, Equatable {
    public enum PlaybackStatus: String, Codable, Sendable {
        case playing
        case paused
        case stopped
    }

    public let stationID: String
    public let stationName: String
    public let trackTitle: String?
    public let artist: String?
    /// Token of the artwork staged in ``NowPlayingWidgetStore``, or `nil` when
    /// the station has no usable artwork (the widget shows its glyph).
    public let artworkToken: String?
    public let status: PlaybackStatus
    /// A ready-to-open deep link back to this station. Built app-side, where
    /// `StationLink` lives, for the same reason as `QuickPlayStationSnapshot`.
    public let deepLinkURLString: String
    /// When the app last confirmed this state. The app refreshes it on a timer
    /// while a station is loaded, so an old value means the app is gone.
    public let updatedAt: Date

    /// How long a snapshot stays believable without a refresh. The app rewrites
    /// it every few minutes while a station is loaded (see
    /// `NowPlayingWidgetCoordinator.heartbeatInterval`), so a snapshot older than
    /// this means the app was killed or crashed without writing `.stopped`, and
    /// the widget must not keep claiming the station is on air.
    public static let maximumAge: TimeInterval = 20 * 60

    public init(
        stationID: String,
        stationName: String,
        trackTitle: String?,
        artist: String?,
        artworkToken: String?,
        status: PlaybackStatus,
        deepLinkURLString: String,
        updatedAt: Date,
    ) {
        self.stationID = stationID
        self.stationName = stationName
        self.trackTitle = trackTitle
        self.artist = artist
        self.artworkToken = artworkToken
        self.status = status
        self.deepLinkURLString = deepLinkURLString
        self.updatedAt = updatedAt
    }

    /// Whether the widget should show this snapshot at `date`: a station is
    /// loaded (playing or paused) and the app confirmed it recently.
    public func isShowable(at date: Date) -> Bool {
        status != .stopped && date.timeIntervalSince(updatedAt) < Self.maximumAge
    }

    /// The moment this snapshot stops being showable, for the widget's timeline.
    public var expiresAt: Date {
        updatedAt.addingTimeInterval(Self.maximumAge)
    }

    /// Everything a viewer can see, ignoring `updatedAt`. Two snapshots that
    /// differ only in their heartbeat look identical on screen.
    func hasSameContent(as other: Self) -> Bool {
        stationID == other.stationID
            && stationName == other.stationName
            && trackTitle == other.trackTitle
            && artist == other.artist
            && artworkToken == other.artworkToken
            && status == other.status
            && deepLinkURLString == other.deepLinkURLString
    }
}

/// When the app should ask WidgetKit to reload the Quick Play widget after a
/// now-playing change.
///
/// WidgetKit rations reloads the app requests from the background, *except*
/// while the app is "participating in a user session like Navigation or Now
/// Playing audio" (WWDC21, "Principles of great widgets"): those reloads are
/// immediate and free. A playing station is exactly that, so while playing
/// every change is reloaded. The snapshot file is always written; only the
/// reload is decided here:
///
/// - **Pause and stop reload immediately.** They are user actions, and nothing
///   else is about to arrive that the reload should wait for.
/// - **Everything else settles first.** Album art resolves a few seconds after
///   the title (an iTunes lookup), so a reload at the title would show the
///   station's art and then need a second reload for the cover. Waiting
///   ``settleInterval`` usually folds both into one. A pending reload absorbs
///   whatever arrives before it fires, because it renders the file as it is then.
/// - **While paused**, the app has no active audio session and its reloads are
///   budgeted, so content changes there are coalesced to one per
///   ``minimumPausedReloadInterval``. Little changes while paused anyway.
public enum NowPlayingWidgetReloadPolicy {
    public enum Decision: Equatable, Sendable {
        case reloadNow
        case reloadAt(Date)
        case skip
    }

    public static let settleInterval: TimeInterval = 12
    public static let minimumPausedReloadInterval: TimeInterval = 10 * 60

    public static func decide(
        previous: NowPlayingWidgetSnapshot?,
        next: NowPlayingWidgetSnapshot,
        lastReload: Date?,
        now: Date,
    ) -> Decision {
        let settled = now.addingTimeInterval(settleInterval)
        guard let previous else {
            // Nothing published yet. A first `.stopped` has nothing to replace.
            return next.status == .stopped ? .skip : .reloadAt(settled)
        }
        if previous.stationID != next.stationID {
            return .reloadAt(settled)
        }
        if previous.status != next.status {
            return next.status == .playing ? .reloadAt(settled) : .reloadNow
        }
        if previous.hasSameContent(as: next) {
            // A heartbeat: the file's new `updatedAt` is all that changed.
            return .skip
        }
        guard next.status != .playing, let lastReload else { return .reloadAt(settled) }
        return .reloadAt(max(settled, lastReload.addingTimeInterval(minimumPausedReloadInterval)))
    }
}

/// App Group drop box for the Quick Play widget's now-playing state: one
/// snapshot file plus the artwork it points at.
public enum NowPlayingWidgetStore {
    private static let directoryName = "NowPlayingWidget"
    private static let snapshotFileName = "now-playing.json"

    /// A filesystem-safe token identifying `url`'s artwork.
    ///
    /// FNV-1a over the URL string: deterministic across processes and launches
    /// (the point of not using `Hasher`, which is seeded per launch), so the app
    /// and the widget extension name the same art the same way.
    public static func token(for url: URL) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    /// Test-only override for the container directory, as in
    /// ``QuickPlayFavoritesStore``. Mutated only from test setup/teardown.
    public nonisolated(unsafe) static var directoryURLOverride: URL?

    /// Writes the snapshot, replacing the previous one. `.noFileProtection`
    /// because widgets render before first unlock; nothing here is sensitive.
    @discardableResult
    public static func save(_ snapshot: NowPlayingWidgetSnapshot) -> Bool {
        guard let directory = directoryURL else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(
                to: directory.appendingPathComponent(snapshotFileName),
                options: [.atomic, .noFileProtection],
            )
            return true
        } catch {
            return false
        }
    }

    /// The staged snapshot, or `nil` if none is staged or it can't be read.
    public static func load() -> NowPlayingWidgetSnapshot? {
        guard let directory = directoryURL,
              let data = try? Data(contentsOf: directory.appendingPathComponent(snapshotFileName))
        else { return nil }
        return try? JSONDecoder().decode(NowPlayingWidgetSnapshot.self, from: data)
    }

    /// Writes artwork PNG bytes under `token`. Does not purge; see ``purgeArtwork(keeping:)``.
    @discardableResult
    public static func stageArtwork(_ pngData: Data, forToken token: String) -> Bool {
        guard let directory = directoryURL, let url = artworkURL(for: token) else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try pngData.write(to: url, options: [.atomic, .noFileProtection])
            return true
        } catch {
            return false
        }
    }

    /// The staged artwork for `token`, or `nil` if nothing is staged for it.
    public static func artworkFileURL(forToken token: String) -> URL? {
        guard let url = artworkURL(for: token) else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Deletes staged artwork whose token is not in `tokens`. The snapshot file
    /// is never touched.
    public static func purgeArtwork(keeping tokens: Set<String>) {
        guard let directory = directoryURL else { return }
        let keep = Set(tokens.map { "\($0).png" })
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
        )) ?? []
        for file in contents where file.pathExtension == "png" && keep.contains(file.lastPathComponent) == false {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static var directoryURL: URL? {
        if let directoryURLOverride {
            return directoryURLOverride
        }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: QuickPlayFavoritesStore.appGroupIdentifier)?
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func artworkURL(for token: String) -> URL? {
        directoryURL?.appendingPathComponent(token, isDirectory: false).appendingPathExtension("png")
    }
}
