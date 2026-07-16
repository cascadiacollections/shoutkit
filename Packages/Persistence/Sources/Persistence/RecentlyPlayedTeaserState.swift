import Foundation

/// The station IDs shown in a bounded "Recently Played" teaser (e.g. Listen Now),
/// deliberately decoupled from a live `prefix(capacity)` over the full history.
///
/// Dismissing an entry shrinks the list rather than backfilling the next-oldest
/// play into its slot; a slot only refills when a genuinely new play lands at
/// the top of the source history.
public struct RecentlyPlayedTeaserState: Equatable, Sendable {
    public private(set) var displayedIDs: [String]
    public let capacity: Int

    public init(capacity: Int = 5) {
        precondition(capacity > 0, "capacity must be positive")
        self.displayedIDs = []
        self.capacity = capacity
    }

    /// Reconciles the teaser against the current history, newest-first and
    /// already excluding anything the caller considers hidden/deleted.
    ///
    /// - On first sync (empty state), seeds up to `capacity` entries.
    /// - Otherwise only reacts to a *new* top entry: promotes it to the front
    ///   and trims the oldest entry if that pushes the list over capacity.
    ///   Removing entries never triggers a backfill from `visibleIDsNewestFirst`.
    public mutating func sync(withVisibleIDsNewestFirst visibleIDsNewestFirst: [String]) {
        guard let latestID = visibleIDsNewestFirst.first else {
            displayedIDs = []
            return
        }
        if displayedIDs.isEmpty {
            displayedIDs = Array(visibleIDsNewestFirst.prefix(capacity))
            return
        }
        guard displayedIDs.first != latestID else { return }
        displayedIDs.removeAll { $0 == latestID }
        displayedIDs.insert(latestID, at: 0)
        if displayedIDs.count > capacity {
            displayedIDs.removeLast(displayedIDs.count - capacity)
        }
    }

    /// Dismisses an entry from the teaser. Does not backfill.
    public mutating func remove(_ id: String) {
        displayedIDs.removeAll { $0 == id }
    }
}
