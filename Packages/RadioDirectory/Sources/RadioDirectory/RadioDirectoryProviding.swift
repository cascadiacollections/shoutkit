import Algorithms
import Foundation

public protocol RadioDirectoryProviding: Sendable {
    func genres() async throws(RadioDirectoryError) -> [Genre]
    func topStations(limit: Int) async throws(RadioDirectoryError) -> [Station]
    func searchStations(matching query: String, limit: Int) async throws(RadioDirectoryError) -> [Station]
    /// Stations belonging to a genre/tag, ordered by popularity where the
    /// directory supports it. Distinct from `searchStations`, which matches names.
    func stations(inGenre genre: String, limit: Int) async throws(RadioDirectoryError) -> [Station]
    func streamEndpoint(for station: Station) async throws(RadioDirectoryError) -> StreamEndpoint
}

public extension RadioDirectoryProviding {
    /// Fallback for directories without a dedicated genre query: a plain search,
    /// which for the simple directories here also matches the genre field.
    func stations(inGenre genre: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        try await searchStations(matching: genre, limit: limit)
    }
}

public enum PreferredStations {
    public static let all: [Station] = [
        kexpHighBandwidth,
        kexpLowBandwidth
    ]

    public static let kexpHighBandwidth = Station(
        id: "preferred-kexp-160-aac",
        name: "KEXP 90.3 FM",
        genre: "Eclectic / Indie",
        listenerCount: 0,
        bitrate: 160,
        artworkURL: URL(string: "https://www.kexp.org/static/assets/img/icons/apple-touch-icon.png"),
        preferredStreamURL: URL(string: "https://kexp.streamguys1.com/kexp160.aac")
    )

    public static let kexpLowBandwidth = Station(
        id: "preferred-kexp-64-aac",
        name: "KEXP 64K AAC",
        genre: "Eclectic / Indie",
        listenerCount: 0,
        bitrate: 64,
        artworkURL: URL(string: "https://www.kexp.org/static/assets/img/icons/apple-touch-icon.png"),
        preferredStreamURL: URL(string: "https://kexp.streamguys1.com/kexp64.aac")
    )
}

public struct PreferredRadioDirectory: RadioDirectoryProviding {
    private let base: any RadioDirectoryProviding
    private let preferredStations: [Station]

    public init(
        base: any RadioDirectoryProviding,
        preferredStations: [Station] = PreferredStations.all
    ) {
        self.base = base
        self.preferredStations = preferredStations
    }

    public func genres() async throws(RadioDirectoryError) -> [Genre] {
        let genres = try await base.genres()
        let preferredGenres = preferredStations.map { Genre(name: $0.genre) }
        return (preferredGenres + genres).uniqued { $0.name.lowercased() }
    }

    public func topStations(limit: Int) async throws(RadioDirectoryError) -> [Station] {
        let remainingLimit = max(limit - preferredStations.count, 0)
        let stations = try await base.topStations(limit: remainingLimit)
        return Array((preferredStations + stations).uniqued { $0.name.lowercased() }.prefix(limit))
    }

    public func searchStations(matching query: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            return []
        }

        let preferredMatches = preferredStations.filter { station in
            station.name.localizedStandardContains(trimmedQuery)
                || station.genre.localizedStandardContains(trimmedQuery)
        }

        let baseLimit = max(limit - preferredMatches.count, 0)
        let stations = try await base.searchStations(matching: query, limit: baseLimit)
        return Array((preferredMatches + stations).uniqued { $0.name.lowercased() }.prefix(limit))
    }

    public func stations(inGenre genre: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        // Forward to the base's real genre query (the protocol default would
        // degrade this into a name search), layering matching preferred stations
        // on top as everywhere else.
        let preferredMatches = preferredStations.filter { station in
            station.genre.localizedCaseInsensitiveContains(genre)
        }

        let baseLimit = max(limit - preferredMatches.count, 0)
        let stations = try await base.stations(inGenre: genre, limit: baseLimit)
        return Array((preferredMatches + stations).uniqued { $0.name.lowercased() }.prefix(limit))
    }

    public func streamEndpoint(for station: Station) async throws(RadioDirectoryError) -> StreamEndpoint {
        if let preferredStreamURL = station.preferredStreamURL {
            return StreamEndpoint(
                stationID: station.id,
                url: preferredStreamURL,
                format: StreamFormat(url: preferredStreamURL)
            )
        }

        return try await base.streamEndpoint(for: station)
    }
}

public struct BundledRadioDirectory: RadioDirectoryProviding {
    private let stations: [Station]

    public init(stations: [Station] = PreferredStations.all) {
        self.stations = stations
    }

    public func genres() async throws(RadioDirectoryError) -> [Genre] {
        stations.map { Genre(name: $0.genre) }.uniqued { $0.name.lowercased() }
    }

    public func topStations(limit: Int) async throws(RadioDirectoryError) -> [Station] {
        Array(stations.prefix(limit))
    }

    public func searchStations(matching query: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            return []
        }

        let matches = stations.filter { station in
            station.name.localizedStandardContains(trimmedQuery)
                || station.genre.localizedStandardContains(trimmedQuery)
        }

        return Array(matches.prefix(limit))
    }

    public func streamEndpoint(for station: Station) async throws(RadioDirectoryError) -> StreamEndpoint {
        guard let streamURL = station.preferredStreamURL else {
            throw RadioDirectoryError.emptyPlaylist
        }

        return StreamEndpoint(
            stationID: station.id,
            url: streamURL,
            format: StreamFormat(url: streamURL)
        )
    }
}

public struct PreviewRadioDirectory: RadioDirectoryProviding {
    public init() {}

    public func genres() async throws(RadioDirectoryError) -> [Genre] {
        [
            Genre(name: "Electronic", stationCount: 128),
            Genre(name: "Jazz", stationCount: 84),
            Genre(name: "Public Radio", stationCount: 51)
        ]
    }

    public func topStations(limit: Int) async throws(RadioDirectoryError) -> [Station] {
        Array(Self.sampleStations.prefix(limit))
    }

    public func searchStations(matching query: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        guard query.isEmpty == false else {
            return []
        }

        return Array(Self.sampleStations.filter { station in
            station.name.localizedStandardContains(query) || station.genre.localizedStandardContains(query)
        }.prefix(limit))
    }

    public func streamEndpoint(for station: Station) async throws(RadioDirectoryError) -> StreamEndpoint {
        let fallbackURL = URL(string: "https://example.com/\(station.id).m3u8")

        return StreamEndpoint(
            stationID: station.id,
            url: fallbackURL ?? URL(fileURLWithPath: "/dev/null"),
            format: .hls
        )
    }

    public static let sampleStations: [Station] = [
        PreferredStations.kexpHighBandwidth,
        PreferredStations.kexpLowBandwidth,
        Station(id: "ambient-current", name: "Ambient Current", genre: "Electronic", listenerCount: 1842, bitrate: 128),
        Station(id: "midnight-jazz", name: "Midnight Jazz", genre: "Jazz", listenerCount: 1320, bitrate: 192),
        Station(id: "city-signal", name: "City Signal", genre: "Public Radio", listenerCount: 966, bitrate: 128),
        Station(id: "deep-orbit", name: "Deep Orbit", genre: "Electronic", listenerCount: 724, bitrate: 256)
    ]
}
