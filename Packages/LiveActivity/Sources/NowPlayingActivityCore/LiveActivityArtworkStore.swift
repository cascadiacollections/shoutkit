import Foundation

/// Shared drop box for the now-playing artwork the Live Activity renders.
///
/// A Live Activity view can't reach the network, and the activity content state
/// is far too small to carry a bitmap, so the app process is the only place the
/// artwork can be produced: it downsamples the current art and writes a PNG into
/// the App Group container this type owns. The widget extension — which links the
/// same `NowPlayingActivityCore` — reads the file back by token.
///
/// Tokens are a stable hash of the source URL, so the same art maps to the same
/// file across launches and processes (unlike `Hasher`, which is seeded per
/// launch). The content state carries only the token; the bytes never travel
/// through ActivityKit.
public enum LiveActivityArtworkStore {
    /// The App Group both the app and the widget extension are entitled to. Must
    /// stay in sync with `ShoutKitApp.entitlements` / `ShoutKitWidgets.entitlements`.
    public static let appGroupIdentifier = "group.com.cascadiacollections.shoutkit"

    /// Subdirectory inside the container so artwork can't collide with anything
    /// else the group might hold later.
    private static let directoryName = "LiveActivityArtwork"
    /// Test-only override for the container directory, so tests can stage files
    /// in an isolated temp directory without an App Group. Mutated only from
    /// test setup/teardown (never concurrently), hence `nonisolated(unsafe)`.
    nonisolated(unsafe) static var directoryURLOverride: URL?

    /// A filesystem-safe token identifying `url`'s artwork.
    ///
    /// FNV-1a over the URL string: deterministic across processes and launches
    /// (the point of not using `Hashable`), and collision-resistant enough for a
    /// single-item cache that only ever holds the current track's art.
    public static func token(for url: URL) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// The file for a staged token, or `nil` if nothing is staged for it. Read
    /// side, used by the widget.
    public static func fileURL(forToken token: String) -> URL? {
        guard let url = fileURL(for: token) else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Writes `pngData` under `token`. Write side, used by the app.
    ///
    /// Deliberately does NOT purge older files: staging runs off the main
    /// actor and can complete late for a download that has already been
    /// superseded — purging here could delete the file the activity currently
    /// points at. The coordinator purges after an update carrying a token has
    /// been *applied* to the activity, keeping every token that can still be
    /// referenced (see ``purge(keeping:)``).
    ///
    /// `.noFileProtection`: the Live Activity renders on the lock screen while the
    /// device is locked, and the default protection class would make the file
    /// unreadable exactly then. Cover art isn't sensitive, so this is safe.
    /// - Returns: `token` on success, `nil` if the container is unavailable or the
    ///   write fails.
    @discardableResult
    public static func stage(_ pngData: Data, forToken token: String) -> String? {
        guard let directory = directoryURL, let fileURL = fileURL(for: token) else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try pngData.write(to: fileURL, options: [.atomic, .noFileProtection])
            return token
        } catch {
            return nil
        }
    }

    /// Drops every staged file except `token`'s — the cache only ever needs the
    /// art currently on screen.
    public static func purge(except token: String? = nil) {
        purge(keeping: token.map { [$0] } ?? [])
    }

    /// Drops every staged file whose token is not in `tokens`.
    ///
    /// The keep-set form exists because more than one file can still be live at
    /// once: the token referenced by the activity state currently applied, the
    /// token the coordinator has adopted but not yet pushed, and a download
    /// staged but not yet adopted. Purging with only one survivor deletes a
    /// file some surface can still re-render, which falls back to the glyph.
    public static func purge(keeping tokens: Set<String>) {
        guard let directory = directoryURL else { return }
        let keep = Set(tokens.map { "\($0).png" })
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for file in contents where keep.contains(file.lastPathComponent) == false {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static var directoryURL: URL? {
        if let directoryURLOverride {
            return directoryURLOverride
        }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func fileURL(for token: String) -> URL? {
        directoryURL?.appendingPathComponent(token, isDirectory: false).appendingPathExtension("png")
    }
}
