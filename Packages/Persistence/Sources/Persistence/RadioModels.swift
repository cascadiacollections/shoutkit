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
    public var artworkURLString: String?
    public var streamURLString: String?
    public var playedAt: Date

    public init(
        stationID: String,
        name: String,
        genre: String,
        artworkURLString: String? = nil,
        streamURLString: String? = nil,
        playedAt: Date = .now
    ) {
        self.stationID = stationID
        self.name = name
        self.genre = genre
        self.artworkURLString = artworkURLString
        self.streamURLString = streamURLString
        self.playedAt = playedAt
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
public final class RecentlyHeardTrack {
    public var stationID: String
    public var stationName: String
    public var title: String?
    public var artist: String?
    public var heardAt: Date
    public var appleMusicURLString: String?

    public init(
        stationID: String,
        stationName: String,
        title: String?,
        artist: String?,
        heardAt: Date = .now,
        appleMusicURLString: String? = nil
    ) {
        self.stationID = stationID
        self.stationName = stationName
        self.title = title
        self.artist = artist
        self.heardAt = heardAt
        self.appleMusicURLString = appleMusicURLString
    }
}
