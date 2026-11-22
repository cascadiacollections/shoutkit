import Foundation
import SwiftData

/// Version 1 of the library schema: the shape every build wrote up to
/// 2026-11-22, when the store was first opened through a migration plan.
///
/// The nested classes are frozen copies. They exist so that a store in this
/// shape can be recognized and migrated; nothing else should use them, and
/// they must never be edited. `stationID` is unique here and is not in
/// ``ShoutKitSchemaV2``.
public enum ShoutKitSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        [
            FavoriteStation.self,
            RecentStation.self,
            RecentlyHeardTrack.self,
        ]
    }

    @Model
    final class FavoriteStation {
        @Attribute(.unique) var stationID: String
        var name: String
        var genre: String
        var artworkURLString: String?
        var streamURLString: String?
        var createdAt: Date
        var sortIndex: Int = 0

        init(
            stationID: String,
            name: String,
            genre: String,
            artworkURLString: String? = nil,
            streamURLString: String? = nil,
            createdAt: Date = .now,
            sortIndex: Int = 0,
        ) {
            self.stationID = stationID
            self.name = name
            self.genre = genre
            self.artworkURLString = artworkURLString
            self.streamURLString = streamURLString
            self.createdAt = createdAt
            self.sortIndex = sortIndex
        }
    }

    @Model
    final class RecentStation {
        @Attribute(.unique) var stationID: String
        var name: String
        var genre: String
        var tagsCSV: String?
        var country: String?
        var codec: String?
        var language: String?
        var clickTrend: Int?
        var votes: Int?
        var bitrate: Int?
        var artworkURLString: String?
        var streamURLString: String?
        var playedAt: Date
        var isHiddenFromListenNow: Bool = false
        var playCount: Int = 1

        init(
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
            playCount: Int = 1,
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
    }

    @Model
    final class RecentlyHeardTrack {
        var stationID: String
        var stationName: String
        var title: String?
        var artist: String?
        var heardAt: Date
        var appleMusicURLString: String?
        var artworkURLString: String?

        init(
            stationID: String,
            stationName: String,
            title: String? = nil,
            artist: String? = nil,
            heardAt: Date = .now,
            appleMusicURLString: String? = nil,
            artworkURLString: String? = nil,
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
}
