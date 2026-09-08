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
        // Keep `nil` for empty/absent tags so optional fields stay omitted when encoded.
        return parsed?.isEmpty == true ? nil : parsed
    }

    /// Serializes tags into a stable comma-separated string for persistence.
    public static func tagsCSV(from tags: [String]?) -> String? {
        guard let tags else { return nil }
        let normalized = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard !normalized.isEmpty else { return nil }
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

    /// A genre strip to paint with before the directory answers.
    ///
    /// The live list is fetched from `/json/tags`, and every path to it is
    /// `async` — `CachingRadioDirectory` is an actor, so even a hit in memory or
    /// on disk is a suspension. Search therefore always painted an empty strip
    /// first and filled it in a moment later, on every single launch, including
    /// launches where the answer was already on the device.
    ///
    /// These are the tags that sit at the top of Radio-Browser's list by station
    /// count, so the seeded strip is close to what replaces it and the swap is
    /// not a visible reshuffle. Capitalised to match `RadioBrowserDirectoryClient`,
    /// which maps tag names through `.capitalized` — a seed in another case would
    /// render as a different chip and then visibly change.
    ///
    /// No `stationCount`: these are a paint-time placeholder, not a claim about
    /// the directory's contents. They are real tags, so selecting one before the
    /// live list lands queries normally.
    public static let paintTimeDefaults: [Genre] = [
        "Pop", "Rock", "News", "Classical", "Jazz", "Talk",
        "Dance", "Country", "Oldies", "Electronic", "Blues", "Metal",
        "Folk", "Soul", "Reggae", "Latin", "Ambient", "Sports"
    ].map { Genre(name: $0) }
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
