import Foundation
import OSLog

public actor ShoutcastDirectoryClient: RadioDirectoryProviding {
    private let apiKey: String
    private let endpoints: ShoutcastEndpoints
    private let session: URLSession
    private let retryPolicy: RetryPolicy
    private let logger = Logger(subsystem: "ShoutKit.RadioDirectory", category: "ShoutcastDirectoryClient")

    public init(
        apiKey: String,
        endpoints: ShoutcastEndpoints = .production,
        session: URLSession = .shared,
        retryPolicy: RetryPolicy = .default
    ) {
        self.apiKey = apiKey
        self.endpoints = endpoints
        self.session = session
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
        let playlist = String(decoding: data, as: UTF8.self)
        let streamURL = try PlaylistParser.firstStreamURL(in: playlist)

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

        var request = URLRequest(url: url, timeoutInterval: retryPolicy.timeout)
        request.setValue("ShoutKit/0.1", forHTTPHeaderField: "User-Agent")

        var lastError: RadioDirectoryError?

        for attempt in 0...retryPolicy.maximumRetries {
            do {
                return try await performRequest(request)
            } catch {
                lastError = error
                guard attempt < retryPolicy.maximumRetries else {
                    break
                }

                let delay = retryPolicy.delay(forAttempt: attempt)
                logger.debug("Directory request failed; retrying in \(delay, privacy: .public) seconds")
                // A cancelled sleep just skips the backoff; the next attempt's
                // network call fails fast on cancellation anyway.
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? .transport(nil)
    }

    private func performRequest(_ request: URLRequest) async throws(RadioDirectoryError) -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw .invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw .httpStatus(httpResponse.statusCode)
        }

        return data
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

    public func legacyURL(endpoint: String, apiKey: String, queryItems: [URLQueryItem]) throws(RadioDirectoryError) -> URL {
        let endpointURL = legacyBaseURL.appendingPathComponent(endpoint)
        var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "k", value: apiKey)] + queryItems

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
            message ?? String(localized: "The station directory could not be reached. Check your connection.", bundle: .module)
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
}

enum PlaylistParser {
    static func firstStreamURL(in playlist: String) throws(RadioDirectoryError) -> URL {
        let lines = playlist
            .split(whereSeparator: \.isNewline)
            .map { line in line.trimmingCharacters(in: .whitespacesAndNewlines) }

        for line in lines where line.localizedCaseInsensitiveContains("File") {
            guard let value = line.split(separator: "=", maxSplits: 1).last else {
                continue
            }

            if let url = URL(string: String(value)) {
                return url
            }
        }

        for line in lines where line.hasPrefix("http://") || line.hasPrefix("https://") {
            if let url = URL(string: line) {
                return url
            }
        }

        throw RadioDirectoryError.emptyPlaylist
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
        guard elementName.localizedCaseInsensitiveCompare("genre") == .orderedSame else {
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
        guard elementName.localizedCaseInsensitiveCompare("station") == .orderedSame else {
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
                name: name,
                genre: genre,
                listenerCount: listeners,
                bitrate: bitrate
            )
        )
    }
}
