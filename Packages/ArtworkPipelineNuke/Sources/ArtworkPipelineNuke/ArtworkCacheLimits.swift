import Foundation

/// Memory and disk ceilings for the shared artwork pipeline.
///
/// The app can hold a handful of Now Playing heroes (an 840 px bitmap is about
/// 2.8 MB) plus a screenful of list thumbnails. An app extension cannot: a
/// widget is jetsam-killed around 30 MB for the whole process, and the Quick
/// Play widget does not load artwork through this pipeline today (it reads a
/// file the app already wrote). The extension numbers are what the pipeline
/// uses if it is ever created inside an `.appex`, so a later call site cannot
/// accidentally adopt the app's budget.
struct ArtworkCacheLimits: Equatable, Sendable {
    /// Decoded bitmaps, in bytes. Nuke enforces this as a hard LRU cap.
    var memoryCostBytes: Int
    /// How many decoded images may sit in memory at once.
    var memoryCountLimit: Int
    /// Largest single bitmap as a fraction of ``memoryCostBytes``. Nuke's
    /// default (0.1) would refuse an 840 px hero in a cache this size.
    var memoryEntryCostFraction: Double
    /// Original encoded bytes on disk.
    var diskByteLimit: Int

    /// App budget. 24 MB holds the previous worst case (about six heroes) and
    /// still leaves room for list thumbnails. 32 MB of encoded originals is
    /// enough for logos and album art without approaching Nuke's 150 MB default.
    static let application = ArtworkCacheLimits(
        memoryCostBytes: 24 * 1024 * 1024,
        memoryCountLimit: 80,
        memoryEntryCostFraction: 0.4,
        diskByteLimit: 32 * 1024 * 1024,
    )

    /// Extension budget. 4 MB of decoded images and 8 MB on disk stay well
    /// under the widget memory limit even if several logos are on screen.
    static let appExtension = ArtworkCacheLimits(
        memoryCostBytes: 4 * 1024 * 1024,
        memoryCountLimit: 12,
        memoryEntryCostFraction: 0.5,
        diskByteLimit: 8 * 1024 * 1024,
    )

    static var current: ArtworkCacheLimits {
        isRunningInAppExtension ? appExtension : application
    }

    /// `Bundle.main` in an extension is the `.appex`, not the containing app.
    static var isRunningInAppExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }
}
