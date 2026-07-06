import Foundation

public struct Station: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let genre: String
    public let listenerCount: Int
    public let bitrate: Int?
    public let artworkURL: URL?
    public let preferredStreamURL: URL?

    public init(
        id: String,
        name: String,
        genre: String,
        listenerCount: Int,
        bitrate: Int? = nil,
        artworkURL: URL? = nil,
        preferredStreamURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.genre = genre
        self.listenerCount = listenerCount
        self.bitrate = bitrate
        self.artworkURL = artworkURL
        self.preferredStreamURL = preferredStreamURL
    }
}

public struct Genre: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String { name }

    public let name: String
    public let stationCount: Int?

    public init(name: String, stationCount: Int? = nil) {
        self.name = name
        self.stationCount = stationCount
    }
}

public struct StreamEndpoint: Codable, Equatable, Hashable, Sendable {
    public let stationID: Station.ID
    public let url: URL
    public let format: StreamFormat

    public init(stationID: Station.ID, url: URL, format: StreamFormat) {
        self.stationID = stationID
        self.url = url
        self.format = format
    }
}

public enum StreamFormat: String, Codable, Sendable {
    case aac
    case hls
    case mp3
    case unknown

    public init(url: URL) {
        let pathExtension = url.pathExtension.lowercased()

        switch pathExtension {
        case "aac":
            self = .aac
        case "m3u8":
            self = .hls
        case "mp3":
            self = .mp3
        default:
            self = .unknown
        }
    }
}

public struct NowPlayingMetadata: Codable, Equatable, Hashable, Sendable {
    public let stationID: Station.ID
    public let title: String?
    public let artist: String?
    public let receivedAt: Date

    public init(stationID: Station.ID, title: String?, artist: String?, receivedAt: Date) {
        self.stationID = stationID
        self.title = title
        self.artist = artist
        self.receivedAt = receivedAt
    }
}
