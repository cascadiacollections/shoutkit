import Foundation
import RadioDirectory
import SwiftData

// MARK: - Recently heard tracks

public extension LibraryStore {
    /// Records parsed now-playing metadata as local track history, de-duplicating
    /// only consecutive repeats and trimming to `recentlyHeardLimit`.
    func logRecentlyHeardTrack(
        station: Station,
        title: String?,
        artist: String?,
        heardAt: Date = .now,
        appleMusicURL: URL? = nil
    ) {
        guard title != nil || artist != nil else { return }

        var singleTrackDescriptor = FetchDescriptor<RecentlyHeardTrack>(
            sortBy: [SortDescriptor(\.heardAt, order: .reverse)]
        )
        singleTrackDescriptor.fetchLimit = 1

        if let latest = try? context.fetch(singleTrackDescriptor).first,
           latest.stationID == station.id,
           latest.title == title,
           latest.artist == artist {
            // Consecutive dedupe keeps one row but refreshes its timestamp so it
            // reflects the most recent hearing of that still-current track.
            latest.stationName = station.name
            latest.heardAt = heardAt
            if let appleMusicURL {
                latest.appleMusicURLString = appleMusicURL.absoluteString
            }
        } else {
            let track = RecentlyHeardTrack(
                stationID: station.id,
                stationName: station.name,
                title: title,
                artist: artist,
                heardAt: heardAt,
                appleMusicURLString: appleMusicURL?.absoluteString
            )
            context.insert(track)
        }

        trimRecentlyHeardTracks()
        save(operation: "log recently heard track \(sanitizedForLogs(station.id))")
    }
}

extension LibraryStore {
    private func trimRecentlyHeardTracks() {
        var trimDescriptor = FetchDescriptor<RecentlyHeardTrack>(
            sortBy: [SortDescriptor(\.heardAt, order: .reverse)]
        )
        trimDescriptor.fetchLimit = Self.recentlyHeardLimit + Self.recentlyHeardTrimHeadroom

        guard let tracks = try? context.fetch(trimDescriptor), tracks.count > Self.recentlyHeardLimit else {
            return
        }

        for stale in tracks[Self.recentlyHeardLimit...] {
            context.delete(stale)
        }
    }
}
