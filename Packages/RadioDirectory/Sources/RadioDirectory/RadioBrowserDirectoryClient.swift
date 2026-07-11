import Foundation
import OSLog

/// Reports that a station was actually played, so a community directory can count
/// popularity. Fire-and-forget: failures must never affect playback.
public protocol StationPlayReporting: Sendable {
    func reportPlay(stationID: String) async
}

/// Directory client for Radio-Browser (radio-browser.info) — a free, open-source,
/// keyless community radio directory. Unlike SHOUTcast, responses are JSON and
/// station objects carry a directly playable `url_resolved`, so no PLS/M3U
/// resolution step is needed.
///
/// The service is DNS-load-balanced across community mirrors with no single fixed
/// endpoint; requests walk `hosts` in order so a dead mirror doesn't take
/// discovery down. Etiquette per the API docs: send a descriptive User-Agent, and
/// report plays via `/json/url/{stationuuid}` (see ``reportPlay(stationID:)``).
public actor RadioBrowserDirectoryClient: RadioDirectoryProviding, StationPlayReporting {
    /// `all.api.radio-browser.info` round-robins across healthy mirrors at the DNS
    /// level; the named mirrors are direct fallbacks if it misbehaves.
    public static let defaultHosts: [URL] = [
        URL(string: "https://all.api.radio-browser.info") ?? URL(fileURLWithPath: "/"),
        URL(string: "https://de1.api.radio-browser.info") ?? URL(fileURLWithPath: "/"),
        URL(string: "https://nl1.api.radio-browser.info") ?? URL(fileURLWithPath: "/")
    ]

    private let hosts: [URL]
    private let session: URLSession
    private let retryPolicy: RetryPolicy
    private let logger = Logger(subsystem: "ShoutKit.RadioDirectory", category: "RadioBrowserDirectoryClient")

    public init(
        hosts: [URL] = RadioBrowserDirectoryClient.defaultHosts,
        session: URLSession = .shared,
        retryPolicy: RetryPolicy = .default
    ) {
        self.hosts = hosts.isEmpty ? RadioBrowserDirectoryClient.defaultHosts : hosts
        self.session = session
        self.retryPolicy = retryPolicy
    }

    // MARK: - RadioDirectoryProviding

    public func genres() async throws(RadioDirectoryError) -> [Genre] {
        let data = try await request(
            path: "/json/tags",
            queryItems: [
                URLQueryItem(name: "order", value: "stationcount"),
                URLQueryItem(name: "reverse", value: "true"),
                URLQueryItem(name: "hidebroken", value: "true"),
                URLQueryItem(name: "limit", value: "48")
            ]
        )

        let tags = try decode([RadioBrowserTag].self, from: data)
        return tags.compactMap { tag in
            let name = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.isEmpty == false else { return nil }
            return Genre(name: name.capitalized, stationCount: tag.stationcount)
        }
    }

    public func topStations(limit: Int) async throws(RadioDirectoryError) -> [Station] {
        let data = try await request(
            path: "/json/stations/topclick",
            queryItems: [
                URLQueryItem(name: "limit", value: String(max(limit, 1))),
                URLQueryItem(name: "hidebroken", value: "true")
            ]
        )

        let stations = try decode([RadioBrowserStation].self, from: data)
        return Array(stations.compactMap(Self.station(from:)).prefix(limit))
    }

    public func searchStations(matching query: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            return []
        }

        let data = try await request(
            path: "/json/stations/search",
            queryItems: [
                URLQueryItem(name: "name", value: trimmedQuery),
                URLQueryItem(name: "limit", value: String(max(limit, 1))),
                URLQueryItem(name: "hidebroken", value: "true"),
                URLQueryItem(name: "order", value: "clickcount"),
                URLQueryItem(name: "reverse", value: "true")
            ]
        )

        let stations = try decode([RadioBrowserStation].self, from: data)
        return Array(stations.compactMap(Self.station(from:)).prefix(limit))
    }

    public func stations(inGenre genre: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        let trimmedGenre = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedGenre.isEmpty == false else {
            return []
        }

        // Radio-Browser tags are stored lowercase; `genres()` capitalizes for display.
        let data = try await request(
            path: "/json/stations/search",
            queryItems: [
                URLQueryItem(name: "tag", value: trimmedGenre.lowercased()),
                URLQueryItem(name: "limit", value: String(max(limit, 1))),
                URLQueryItem(name: "hidebroken", value: "true"),
                URLQueryItem(name: "order", value: "clickcount"),
                URLQueryItem(name: "reverse", value: "true")
            ]
        )

        let stations = try decode([RadioBrowserStation].self, from: data)
        return Array(stations.compactMap(Self.station(from:)).prefix(limit))
    }

    public func streamEndpoint(for station: Station) async throws(RadioDirectoryError) -> StreamEndpoint {
        if let preferredStreamURL = station.preferredStreamURL {
            return StreamEndpoint(
                stationID: station.id,
                url: preferredStreamURL,
                format: StreamFormat(url: preferredStreamURL)
            )
        }

        // A station that lost its snapshot URL (e.g. an old persisted record) can
        // still be re-resolved by UUID.
        let data = try await request(
            path: "/json/stations/byuuid",
            queryItems: [URLQueryItem(name: "uuids", value: station.id)]
        )

        let stations = try decode([RadioBrowserStation].self, from: data)
        guard let resolved = stations.compactMap(Self.station(from:)).first,
              let streamURL = resolved.preferredStreamURL else {
            throw RadioDirectoryError.emptyPlaylist
        }

        return StreamEndpoint(
            stationID: station.id,
            url: streamURL,
            format: StreamFormat(url: streamURL)
        )
    }

    // MARK: - StationPlayReporting

    /// Radio-Browser etiquette: `GET /json/url/{stationuuid}` when a station is
    /// actually played, so the community directory can rank popularity. Only
    /// stations sourced from Radio-Browser have UUID identifiers — bundled or
    /// SHOUTcast stations are skipped rather than sending garbage requests.
    public func reportPlay(stationID: String) async {
        guard UUID(uuidString: stationID) != nil else { return }
        _ = try? await request(path: "/json/url/\(stationID)", queryItems: [])
    }

    // MARK: - Mapping

    static func station(from dto: RadioBrowserStation) -> Station? {
        let name = dto.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard name.isEmpty == false, dto.stationuuid.isEmpty == false else {
            return nil
        }

        // `url_resolved` is the directly playable stream; fall back to `url`.
        let rawStream = [dto.urlResolved, dto.url]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.isEmpty == false }
        guard let rawStream, let streamURL = URL(string: rawStream) else {
            return nil
        }

        return Station(
            id: dto.stationuuid,
            name: name,
            genre: genre(from: dto),
            listenerCount: 0,
            bitrate: (dto.bitrate ?? 0) > 0 ? dto.bitrate : nil,
            artworkURL: artworkURL(from: dto.favicon),
            preferredStreamURL: streamURL
        )
    }

    static func genre(from dto: RadioBrowserStation) -> String {
        let firstTag = dto.tags?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.isEmpty == false }

        if let firstTag {
            return firstTag.capitalized
        }

        let country = dto.country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return country.isEmpty ? "Radio" : country
    }

    /// Favicons are frequently plain http://, which ATS blocks for image loads
    /// (the app's ATS exception covers AV media only). Upgrading to https is a
    /// best-effort heuristic — if the host doesn't support it, the artwork
    /// placeholder shows instead.
    static func artworkURL(from favicon: String?) -> URL? {
        let trimmed = favicon?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false, var components = URLComponents(string: trimmed) else {
            return nil
        }

        if components.scheme == "http" {
            components.scheme = "https"
        }

        return components.url
    }

    // MARK: - Transport

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws(RadioDirectoryError) -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw RadioDirectoryError.parsingFailed(
                String(localized: "The Radio-Browser response could not be parsed.", bundle: .module)
            )
        }
    }

    /// Walks the mirror list in order with backoff between attempts, so one dead
    /// mirror doesn't take discovery down.
    private func request(path: String, queryItems: [URLQueryItem]) async throws(RadioDirectoryError) -> Data {
        var lastError: RadioDirectoryError?

        for (attempt, host) in hosts.enumerated() {
            do {
                return try await request(url: url(host: host, path: path, queryItems: queryItems))
            } catch {
                lastError = error
                guard attempt < hosts.count - 1 else { break }

                let delay = retryPolicy.delay(forAttempt: attempt)
                logger.debug("Radio-Browser request failed; trying next mirror in \(delay, privacy: .public) seconds")
                // A cancelled sleep just skips the backoff; the next attempt's
                // network call fails fast on cancellation anyway.
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? .transport(nil)
    }

    private func request(url: URL) async throws(RadioDirectoryError) -> Data {
        var request = URLRequest(url: url, timeoutInterval: retryPolicy.timeout)
        // Radio-Browser asks clients to identify themselves with a speaking agent.
        request.setValue("ShoutKit/0.1", forHTTPHeaderField: "User-Agent")

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

    private func url(host: URL, path: String, queryItems: [URLQueryItem]) throws(RadioDirectoryError) -> URL {
        var components = URLComponents(url: host, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        // `URLComponents` leaves `+` unescaped in query values, but web servers
        // conventionally form-decode it as a space — a search for "C+C Music
        // Factory" would arrive as "C C Music Factory". Escape it explicitly.
        if let escapedQuery = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B") {
            components?.percentEncodedQuery = escapedQuery
        }

        guard let url = components?.url else {
            throw RadioDirectoryError.invalidURL
        }

        return url
    }
}

// MARK: - Wire types

struct RadioBrowserStation: Decodable {
    let stationuuid: String
    let name: String?
    let url: String?
    let urlResolved: String?
    let favicon: String?
    let tags: String?
    let country: String?
    let codec: String?
    let bitrate: Int?
    let clickcount: Int?

    enum CodingKeys: String, CodingKey {
        case stationuuid
        case name
        case url
        case urlResolved = "url_resolved"
        case favicon
        case tags
        case country
        case codec
        case bitrate
        case clickcount
    }
}

struct RadioBrowserTag: Decodable {
    let name: String
    let stationcount: Int?
}
