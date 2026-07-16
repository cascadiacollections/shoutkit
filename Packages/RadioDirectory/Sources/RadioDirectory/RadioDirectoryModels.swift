import Foundation

public struct Station: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let genre: String
    public let tags: [String]?
    public let country: String?
    public let codec: String?
    public let language: String?
    public let listenerCount: Int
    public let bitrate: Int?
    public let clickTrend: Int?
    public let votes: Int?
    public let artworkURL: URL?
    public let preferredStreamURL: URL?

    public init(
        id: String,
        name: String,
        genre: String,
        tags: [String]? = nil,
        country: String? = nil,
        codec: String? = nil,
        language: String? = nil,
        listenerCount: Int,
        bitrate: Int? = nil,
        clickTrend: Int? = nil,
        votes: Int? = nil,
        artworkURL: URL? = nil,
        preferredStreamURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.genre = genre
        self.tags = tags
        self.country = country
        self.codec = codec
        self.language = language
        self.listenerCount = listenerCount
        self.bitrate = bitrate
        self.clickTrend = clickTrend
        self.votes = votes
        self.artworkURL = artworkURL
        self.preferredStreamURL = preferredStreamURL
    }

    /// Parses a comma-separated tag list from directory payloads/persistence.
    public static func tags(fromCSV csv: String?) -> [String]? {
        let parsed = csv?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        return parsed?.isEmpty == false ? parsed : nil
    }

    /// Serializes tags into a stable comma-separated string for persistence.
    public static func tagsCSV(from tags: [String]?) -> String? {
        guard let tags else { return nil }
        let normalized = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard normalized.isEmpty == false else { return nil }
        return normalized.joined(separator: ",")
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
