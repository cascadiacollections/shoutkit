import Foundation

/// How far back a Top Tracks report looks. `nil` from ``since(from:)`` means
/// "no lower bound" — the whole retained history.
public enum TopTracksTimeframe: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case allTime

    public var id: String { rawValue }

    public func since(from now: Date = .now) -> Date? {
        switch self {
        case .week:
            return Calendar.current.date(byAdding: .day, value: -7, to: now)
        case .month:
            return Calendar.current.date(byAdding: .month, value: -1, to: now)
        case .allTime:
            return nil
        }
    }
}

/// One row of a "most played" report: a (title, artist) pair collapsed across
/// every ``RecentlyHeardTrack`` row that matches it, with a play count and the
/// most recently seen cover art / Apple Music link.
public struct TopTrack: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let artist: String
    public let playCount: Int
    public let lastHeardAt: Date
    public let artworkURLString: String?
    public let appleMusicURLString: String?

    public var artworkURL: URL? { artworkURLString.flatMap(URL.init(string:)) }
    public var appleMusicURL: URL? { appleMusicURLString.flatMap(URL.init(string:)) }
}

/// Aggregates local listening history into a "most played" ranking.
///
/// Pure and free of SwiftData: it operates on the array a `@Query` already
/// hands the view, so a Top Tracks screen recomputes reactively for free
/// whenever `RecentlyHeardTrack` rows change, with no separate fetch/store
/// plumbing to keep in sync.
public enum TopTracksAggregator {
    /// - Parameters:
    ///   - tracks: Recently heard rows, in any order.
    ///   - timeframe: How far back to look; `.allTime` considers every row.
    ///   - limit: Maximum rows to return, most-played first.
    ///   - now: Injectable for deterministic tests.
    /// - Returns: Rows sorted by play count descending, ties broken by most
    ///   recently heard. A track needs both a title and an artist to be
    ///   counted — one-sided ICY metadata can't be matched across plays.
    public static func aggregate(
        _ tracks: [RecentlyHeardTrack],
        timeframe: TopTracksTimeframe,
        limit: Int = 20,
        now: Date = .now
    ) -> [TopTrack] {
        let since = timeframe.since(from: now)
        var buckets: [String: TopTrack] = [:]

        for track in tracks {
            guard let title = track.title, let artist = track.artist,
                  title.isEmpty == false, artist.isEmpty == false else { continue }
            if let since, track.heardAt < since { continue }

            let key = "\(title.lowercased())|\(artist.lowercased())"
            if let existing = buckets[key] {
                let isNewer = track.heardAt > existing.lastHeardAt
                buckets[key] = TopTrack(
                    id: key,
                    title: isNewer ? title : existing.title,
                    artist: isNewer ? artist : existing.artist,
                    playCount: existing.playCount + 1,
                    lastHeardAt: max(existing.lastHeardAt, track.heardAt),
                    artworkURLString: isNewer ? track.artworkURLString ?? existing.artworkURLString
                        : existing.artworkURLString ?? track.artworkURLString,
                    appleMusicURLString: isNewer ? track.appleMusicURLString ?? existing.appleMusicURLString
                        : existing.appleMusicURLString ?? track.appleMusicURLString
                )
            } else {
                buckets[key] = TopTrack(
                    id: key,
                    title: title,
                    artist: artist,
                    playCount: 1,
                    lastHeardAt: track.heardAt,
                    artworkURLString: track.artworkURLString,
                    appleMusicURLString: track.appleMusicURLString
                )
            }
        }

        return buckets.values
            .sorted { lhs, rhs in
                lhs.playCount == rhs.playCount ? lhs.lastHeardAt > rhs.lastHeardAt : lhs.playCount > rhs.playCount
            }
            .prefix(limit)
            .map { $0 }
    }
}
