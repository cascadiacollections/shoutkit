import Foundation
import OSLog

// swiftlint:disable file_length

public actor ShoutcastDirectoryClient: RadioDirectoryProviding {
    private let apiKey: String
    private let endpoints: ShoutcastEndpoints
    private let transport: any HTTPTransporting
    private let retryPolicy: RetryPolicy
    private let logger = Logger(subsystem: "ShoutKit.RadioDirectory", category: "ShoutcastDirectoryClient")

    public init(
        apiKey: String,
        endpoints: ShoutcastEndpoints = .production,
        transport: any HTTPTransporting = URLSessionHTTPTransport.shared,
        retryPolicy: RetryPolicy = .default
    ) {
        self.apiKey = apiKey
        self.endpoints = endpoints
        self.transport = transport
        self.retryPolicy = retryPolicy
    }

    public func genres() async throws(RadioDirectoryError) -> [Genre] {
        let data = try await request(endpoint: "genrelist", queryItems: [])
        return try ShoutcastXMLParser.parseGenres(from: data)
    }

    public func topStations(limit: Int) async throws(RadioDirectoryError) -> [Station] {
        let data = try await request(endpoint: "Top500", queryItems: [])
        return Array(try ShoutcastXMLParser.parseStations(from: data).prefix(limit))
    }

    public func searchStations(matching query: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return []
        }

        let data = try await request(
            endpoint: "stationsearch",
            queryItems: [
                URLQueryItem(name: "search", value: query)
            ]
        )

        return Array(try ShoutcastXMLParser.parseStations(from: data).prefix(limit))
    }

    public func stations(inGenre genre: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        guard genre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return []
        }

        let data = try await request(
            endpoint: "genresearch",
            queryItems: [
                URLQueryItem(name: "genre", value: genre)
            ]
        )

        return Array(try ShoutcastXMLParser.parseStations(from: data).prefix(limit))
    }

    public func streamEndpoint(for station: Station) async throws(RadioDirectoryError) -> StreamEndpoint {
        let data = try await request(url: endpoints.tuneInURL(stationID: station.id), requiresAPIKey: false)
        // Playlists are short ASCII/UTF-8 text; decode totally (lossy on stray
        // bytes) rather than failably — PlaylistParser rejects anything without a
        // valid stream URL regardless.
        // swiftlint:disable:next optional_data_string_conversion
        let playlist = String(decoding: data, as: UTF8.self)
        let streamURL = try PlaylistParser.firstStreamURL(
            in: playlist,
            playlistURL: endpoints.tuneInURL(stationID: station.id)
        )

        return StreamEndpoint(
            stationID: station.id,
            url: streamURL,
            format: StreamFormat(url: streamURL)
        )
    }

    private func request(endpoint: String, queryItems: [URLQueryItem]) async throws(RadioDirectoryError) -> Data {
        let url = try endpoints.legacyURL(endpoint: endpoint, apiKey: apiKey, queryItems: queryItems)
        return try await request(url: url, requiresAPIKey: true)
    }

    private func request(url: URL, requiresAPIKey: Bool) async throws(RadioDirectoryError) -> Data {
        if requiresAPIKey, apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw RadioDirectoryError.missingAPIKey
        }

        let transport = self.transport
        let retryPolicy = self.retryPolicy
        let logger = self.logger

        do {
            return try await transport.retryingData(
                retryPolicy: retryPolicy,
                totalAttempts: retryPolicy.maximumRetries + 1,
                shouldRetry: { error in
                    // Retrying a permanent failure (a 4xx from a bad API key,
                    // say) just delays the error surfacing by the whole
                    // backoff window.
                    Self.directoryError(from: error).isRetryable
                },
                onRetry: { _, delay in
                    logger.debug("Directory request failed; retrying in \(delay, privacy: .public) seconds")
                },
                request: { _ in
                    var request = URLRequest(url: url, timeoutInterval: retryPolicy.timeout)
                    request.setValue("ShoutKit/0.1", forHTTPHeaderField: "User-Agent")
                    return request
                }
            )
        } catch {
            throw Self.directoryError(from: error)
        }
    }

    private static func directoryError(from error: Error) -> RadioDirectoryError {
        if let radioDirectoryError = error as? RadioDirectoryError {
            return radioDirectoryError
        }

        if let transportError = error as? HTTPTransportError {
            switch transportError {
            case let .transport(message):
                return .transport(message)
            case .invalidResponse:
                return .invalidResponse
            case let .httpStatus(statusCode):
                return .httpStatus(statusCode)
            }
        }

        return .transport(error.localizedDescription)
    }
}

public struct ShoutcastEndpoints: Sendable {
    public let legacyBaseURL: URL
    public let tuneInBaseURL: URL

    public init(legacyBaseURL: URL, tuneInBaseURL: URL) {
        self.legacyBaseURL = legacyBaseURL
        self.tuneInBaseURL = tuneInBaseURL
    }

    public static let production = ShoutcastEndpoints(
        legacyBaseURL: URL(string: "https://api.shoutcast.com/legacy") ?? URL(fileURLWithPath: "/"),
        tuneInBaseURL: URL(string: "https://yp.shoutcast.com/sbin/tunein-station.pls") ?? URL(fileURLWithPath: "/")
    )

    public func legacyURL(
        endpoint: String,
        apiKey: String,
        queryItems: [URLQueryItem]
    ) throws(RadioDirectoryError) -> URL {
        let endpointURL = legacyBaseURL.appendingPathComponent(endpoint)
        var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "k", value: apiKey)] + queryItems
        components?.escapePlusInQueryValues()

        guard let url = components?.url else {
            throw RadioDirectoryError.invalidURL
        }

        return url
    }

    public func tuneInURL(stationID: Station.ID) -> URL {
        var components = URLComponents(url: tuneInBaseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "id", value: stationID)
        ]

        return components?.url ?? tuneInBaseURL
    }
}

public struct RetryPolicy: Sendable {
    public let maximumRetries: Int
    public let timeout: TimeInterval
    public let baseDelay: TimeInterval

    public init(maximumRetries: Int, timeout: TimeInterval, baseDelay: TimeInterval) {
        self.maximumRetries = maximumRetries
        self.timeout = timeout
        self.baseDelay = baseDelay
    }

    public static let `default` = RetryPolicy(maximumRetries: 2, timeout: 12, baseDelay: 0.35)

    /// For user-facing directory discovery (top stations, genres, search) where a
    /// dead first mirror should fail over fast rather than stalling the screen.
    /// The 5s timeout means a single unhealthy host costs ~5s (plus backoff)
    /// before the next mirror is tried, not the 12s the batch/`default` policy
    /// tolerates for background work.
    public static let interactive = RetryPolicy(maximumRetries: 2, timeout: 5, baseDelay: 0.35)

    public func delay(forAttempt attempt: Int) -> TimeInterval {
        baseDelay * pow(2, Double(attempt))
    }
}

public enum RadioDirectoryError: Error, Equatable, LocalizedError, Sendable {
    case emptyPlaylist
    case httpStatus(Int)
    case invalidResponse
    case invalidURL
    case missingAPIKey
    case parsingFailed(String)
    case transport(String?)

    public var errorDescription: String? {
        switch self {
        case .emptyPlaylist:
            String(localized: "The station did not return a playable stream.", bundle: .module)
        case let .httpStatus(statusCode):
            String(localized: "The station directory returned HTTP \(statusCode).", bundle: .module)
        case .invalidResponse:
            String(localized: "The station directory returned an invalid response.", bundle: .module)
        case .invalidURL:
            String(localized: "The station directory URL could not be built.", bundle: .module)
        case .missingAPIKey:
            String(localized: "Add SHOUTCAST_DEV_KEY to Secrets.xcconfig to fetch live stations.", bundle: .module)
        case let .parsingFailed(message):
            // Constructed at the throw site — either a literal we authored
            // (already wrapped there) or a system-provided description.
            message
        case let .transport(message):
            // System-provided (URLSession's localizedDescription) when non-nil.
            message ?? String(
                localized: "The station directory could not be reached. Check your connection.",
                bundle: .module
            )
        }
    }

    /// Whether retrying the same request might plausibly succeed — lets the UI
    /// distinguish "try again" failures (network) from permanent ones (bad data).
    public var isRetryable: Bool {
        switch self {
        case .transport, .httpStatus, .invalidResponse, .emptyPlaylist:
            true
        case .invalidURL, .missingAPIKey, .parsingFailed:
            false
        }
    }

    /// Friendly, full-length message suitable for the Now Playing screen.
    /// Each case returns a pre-mapped string; the UI layer never interprets
    /// raw error codes.
    public var userMessage: String {
        switch self {
        case .transport:
            String(localized: "Can't reach the station. Check your connection.", bundle: .module)
        case .emptyPlaylist, .httpStatus, .invalidResponse:
            String(localized: "The station isn't available right now.", bundle: .module)
        case .invalidURL, .missingAPIKey, .parsingFailed:
            String(localized: "The station has a configuration problem.", bundle: .module)
        }
    }

    /// Short message suitable for compact surfaces such as the mini player
    /// or lock screen.
    public var shortUserMessage: String {
        switch self {
        case .transport:
            String(localized: "No connection", bundle: .module)
        case .emptyPlaylist, .httpStatus, .invalidResponse:
            String(localized: "Unavailable", bundle: .module)
        case .invalidURL, .missingAPIKey, .parsingFailed:
            String(localized: "Station error", bundle: .module)
        }
    }
}

enum PlaylistParser {
    static func firstStreamURL(
        in playlist: String,
        playlistURL: URL? = nil
    ) throws(RadioDirectoryError) -> URL {
        let lines = playlist
            .split(whereSeparator: \.isNewline)
            .map { line in line.trimmingCharacters(in: .whitespacesAndNewlines) }

        // PLS entries are `FileN=<url>`. Match the key by prefix — a substring
        // match would also hit `Title1=filedrop.fm` — and case-insensitively
        // via locale-independent lowercasing (localized folding breaks the
        // i/I match under e.g. the Turkish locale). A `File` line with no
        // value (`File1=`) is skipped rather than returning the key itself
        // as a relative URL.
        for line in lines where line.lowercased().hasPrefix("file") {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard
                value.isEmpty == false,
                let url = streamURL(from: String(value), playlistURL: playlistURL)
            else {
                continue
            }
            return url
        }

        for line in lines {
            let lowercased = line.lowercased()
            guard lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") else {
                continue
            }
            if let url = URL(string: line) {
                return url
            }
        }

        throw RadioDirectoryError.emptyPlaylist
    }

    private static func streamURL(from value: String, playlistURL: URL?) -> URL? {
        let parsed = URL(string: value, relativeTo: playlistURL)?.absoluteURL
        guard let parsed,
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return parsed
    }
}

enum ShoutcastXMLParser {
    static func parseGenres(from data: Data) throws(RadioDirectoryError) -> [Genre] {
        let delegate = GenreParserDelegate()
        try parse(data: data, delegate: delegate)
        return delegate.genres
    }

    static func parseStations(from data: Data) throws(RadioDirectoryError) -> [Station] {
        let delegate = StationParserDelegate()
        try parse(data: data, delegate: delegate)
        return delegate.stations
    }

    private static func parse(data: Data, delegate: XMLParserDelegate) throws(RadioDirectoryError) {
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let message = parser.parserError?.localizedDescription
                ?? String(localized: "The SHOUTcast XML response could not be parsed.", bundle: .module)
            throw RadioDirectoryError.parsingFailed(message)
        }
    }
}

private final class GenreParserDelegate: NSObject, XMLParserDelegate {
    private(set) var genres: [Genre] = []

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        // Locale-independent: XML element names are protocol tokens, and
        // localized folding fails on i/I under e.g. the Turkish locale.
        guard elementName.caseInsensitiveCompare("genre") == .orderedSame else {
            return
        }

        let name = attributeDict["name"] ?? attributeDict["Name"]
        let count = attributeDict["count"] ?? attributeDict["stationcount"] ?? attributeDict["stationCount"]

        guard let name, name.isEmpty == false else {
            return
        }

        genres.append(Genre(name: name, stationCount: count.flatMap(Int.init)))
    }
}

private final class StationParserDelegate: NSObject, XMLParserDelegate {
    private(set) var stations: [Station] = []

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        // Locale-independent for the same reason as the genre parser above.
        guard elementName.caseInsensitiveCompare("station") == .orderedSame else {
            return
        }

        guard let id = attributeDict["id"], let name = attributeDict["name"], name.isEmpty == false else {
            return
        }

        let genre = attributeDict["genre"] ?? "Unknown"
        let listeners = attributeDict["lc"].flatMap(Int.init) ?? attributeDict["listeners"].flatMap(Int.init) ?? 0
        let bitrate = attributeDict["br"].flatMap(Int.init)

        stations.append(
            Station(
                id: id,
                name: StationNameFormatter.normalize(name),
                genre: genre,
                listenerCount: listeners,
                bitrate: bitrate
            )
        )
    }
}
