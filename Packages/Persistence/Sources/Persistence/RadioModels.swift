import Foundation
import RadioDirectory
import SwiftData

@Model
public final class FavoriteStation {
    @Attribute(.unique) public var stationID: String
    public var name: String
    public var genre: String
    public var artworkURLString: String?
    public var streamURLString: String?
    public var createdAt: Date
    /// User-defined ordering for the Favorites list, ascending (0 = top). A default
    /// value keeps the schema change a lightweight, additive migration; existing rows
    /// migrate to 0 and are re-based on first launch by `LibraryStore`.
    public var sortIndex: Int = 0

    public init(
        stationID: String,
        name: String,
        genre: String,
        artworkURLString: String? = nil,
        streamURLString: String? = nil,
        createdAt: Date = .now,
        sortIndex: Int = 0
    ) {
        self.stationID = stationID
        self.name = name
        self.genre = genre
        self.artworkURLString = artworkURLString
        self.streamURLString = streamURLString
        self.createdAt = createdAt
        self.sortIndex = sortIndex
    }

    public var station: Station {
        Station(
            id: stationID,
            name: name,
            genre: genre,
            listenerCount: 0,
            artworkURL: artworkURLString.flatMap(URL.init(string:)),
            preferredStreamURL: streamURLString.flatMap(URL.init(string:))
        )
    }
}

@Model
public final class RecentStation {
    @Attribute(.unique) public var stationID: String
    public var name: String
    public var genre: String
    public var tagsCSV: String?
    public var country: String?
    public var codec: String?
    public var language: String?
    public var clickTrend: Int?
    public var votes: Int?
    public var bitrate: Int?
    public var artworkURLString: String?
    public var streamURLString: String?
    public var playedAt: Date
    /// Hides this entry from the Listen Now "Recently Played" teaser without
    /// deleting the underlying play record, so recommendation scoring still
    /// sees it as history. A default value keeps this a lightweight, additive
    /// migration, matching `FavoriteStation.sortIndex`. Re-playing the station
    /// clears the flag (see `LibraryStore.logRecent`).
    public var isHiddenFromListenNow: Bool = false
    /// How many times the user has played this station. Incremented on each
    /// `LibraryStore.logRecent`; unlike `playedAt` (overwritten each play) this
    /// accumulates, giving a real "well-trafficked" signal for prewarming and
    /// recommendations rather than mere recency. A default value keeps this a
    /// lightweight additive migration, matching `isHiddenFromListenNow`.
    public var playCount: Int = 1

    public init(
        stationID: String,
        name: String,
        genre: String,
        tagsCSV: String? = nil,
        country: String? = nil,
        codec: String? = nil,
        language: String? = nil,
        clickTrend: Int? = nil,
        votes: Int? = nil,
        bitrate: Int? = nil,
        artworkURLString: String? = nil,
        streamURLString: String? = nil,
        playedAt: Date = .now,
        isHiddenFromListenNow: Bool = false,
        playCount: Int = 1
    ) {
        self.stationID = stationID
        self.name = name
        self.genre = genre
        self.tagsCSV = tagsCSV
        self.country = country
        self.codec = codec
        self.language = language
        self.clickTrend = clickTrend
        self.votes = votes
        self.bitrate = bitrate
        self.artworkURLString = artworkURLString
        self.streamURLString = streamURLString
        self.playedAt = playedAt
        self.isHiddenFromListenNow = isHiddenFromListenNow
        self.playCount = playCount
    }

    public var station: Station {
        Station(
            id: stationID,
            name: name,
            genre: genre,
            tags: Station.tags(fromCSV: tagsCSV),
            country: country,
            codec: codec,
            language: language,
            listenerCount: 0,
            bitrate: bitrate,
            clickTrend: clickTrend,
            votes: votes,
            artworkURL: artworkURLString.flatMap(URL.init(string:)),
            preferredStreamURL: streamURLString.flatMap(URL.init(string:))
        )
    }
}

@Model
public final class RecentlyHeardTrack {
    public var stationID: String
    public var stationName: String
    public var title: String?
    public var artist: String?
    public var heardAt: Date
    public var appleMusicURLString: String?
    /// Cover art resolved for this track by `AlbumArtLookup`, or `nil` when
    /// album art is disabled or the lookup found none. Added alongside
    /// `appleMusicURLString`'s existing pattern — a default keeps this a
    /// lightweight, additive migration for pre-existing rows.
    public var artworkURLString: String?

    public init(
        stationID: String,
        stationName: String,
        title: String?,
        artist: String?,
        heardAt: Date = .now,
        appleMusicURLString: String? = nil,
        artworkURLString: String? = nil
    ) {
        self.stationID = stationID
        self.stationName = stationName
        self.title = title
        self.artist = artist
        self.heardAt = heardAt
        self.appleMusicURLString = appleMusicURLString
        self.artworkURLString = artworkURLString
    }
}
