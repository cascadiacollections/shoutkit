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

    public init(
        stationID: String,
        name: String,
        genre: String,
        artworkURLString: String? = nil,
        streamURLString: String? = nil,
        createdAt: Date = .now
    ) {
        self.stationID = stationID
        self.name = name
        self.genre = genre
        self.artworkURLString = artworkURLString
        self.streamURLString = streamURLString
        self.createdAt = createdAt
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
