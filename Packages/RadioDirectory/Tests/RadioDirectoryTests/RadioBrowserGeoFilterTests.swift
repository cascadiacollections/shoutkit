import Foundation
@testable import RadioDirectory
import Testing

/// Answers by URL path rather than in arrival order: `topStations` issues its
/// regional and global requests concurrently, so their order isn't fixed.
private actor PathRoutingTransport: HTTPTransporting {
    private(set) var requests: [URLRequest] = []
    private let routes: [String: Result<Data, Error>]

    init(_ routes: [String: Result<Data, Error>]) {
        self.routes = routes
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let url = request.url ?? URL(fileURLWithPath: "/")
        guard let route = routes[url.path] else {
            throw HTTPTransportError.transport("No route for \(url.path)")
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        return try (route.get(), response ?? URLResponse())
    }

    func queryItems(forPath path: String) -> [[URLQueryItem]] {
        requests
            .filter { $0.url?.path == path }
            .compactMap { request in
                URLComponents(url: request.url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)?.queryItems
            }
    }
}

private struct StaticGeoFilterProvider: RadioBrowserGeoFilterProviding {
    let geoFilter: RadioBrowserGeoFilter?

    func currentGeoFilter() async -> RadioBrowserGeoFilter? {
        geoFilter
    }
}

private let topClickPath = "/json/stations/topclick"
private let searchPath = "/json/stations/search"

/// A Radio-Browser station list. Each station's UUID is spelled from its name's
/// bytes, so the same name is the same station in both lists.
private func stationsJSON(_ names: [String]) -> Data {
    let items = names.map { name in
        let hex = name.utf8.prefix(16).map { String(format: "%02x", $0) }.joined()
            .padding(toLength: 32, withPad: "0", startingAt: 0)
        let uuid = [8, 4, 4, 4, 12].reduce(into: (parts: [String](), rest: Substring(hex))) { acc, width in
            acc.parts.append(String(acc.rest.prefix(width)))
            acc.rest = acc.rest.dropFirst(width)
        }.parts.joined(separator: "-")
        return """
        {"stationuuid": "\(uuid)", "name": "\(name)", \
        "url": "http://example.com/\(name).mp3", "url_resolved": "http://example.com/\(name).mp3", "bitrate": 128}
        """
    }
    return Data("[\(items.joined(separator: ","))]".utf8)
}

private func client(
    _ transport: PathRoutingTransport,
    country: String?,
) -> RadioBrowserDirectoryClient {
    RadioBrowserDirectoryClient(
        transport: transport,
        retryPolicy: RetryPolicy(maximumRetries: 0, timeout: 1, baseDelay: 0),
        geoFilterProvider: StaticGeoFilterProvider(geoFilter: RadioBrowserGeoFilter(countryCode: country)),
    )
}

struct RadioBrowserGeoFilterTests {
    // MARK: - Filter

    @Test func `locale filter takes the region`() {
        #expect(RadioBrowserGeoFilter(locale: Locale(identifier: "fr_CA")).countryCode == "CA")
    }

    @Test func `a locale with no region gives no country`() {
        #expect(RadioBrowserGeoFilter(locale: Locale(identifier: "en")).countryCode == nil)
    }

    @Test func `country codes are trimmed, uppercased, and blank means none`() {
        #expect(RadioBrowserGeoFilter(countryCode: " jp\n").countryCode == "JP")
        #expect(RadioBrowserGeoFilter(countryCode: "  ").countryCode == nil)
    }

    @Test func `snapshot identity names the country`() {
        #expect(RadioBrowserGeoFilter(countryCode: "US").snapshotIdentity == "country=US")
        #expect(RadioBrowserGeoFilter(countryCode: nil).snapshotIdentity == "country=any")
    }

    @Test func `mutable provider returns latest filter`() async {
        let provider = MutableRadioBrowserGeoFilterProvider()
        #expect(await provider.currentGeoFilter() == nil)
        let geoFilter = RadioBrowserGeoFilter(countryCode: "CA")
        await provider.setCurrentGeoFilter(geoFilter)
        #expect(await provider.currentGeoFilter() == geoFilter)
    }

    // MARK: - Top stations

    @Test func `regional stations come first and global fills the rest without repeats`() async throws {
        let transport = PathRoutingTransport([
            searchPath: .success(stationsJSON(["KEXP", "KUOW"])),
            topClickPath: .success(stationsJSON(["RTL", "KEXP", "FIP", "NHK"])),
        ])

        let stations = try await client(transport, country: "US").topStations(limit: 4)

        #expect(stations.map(\.name) == ["KEXP", "KUOW", "RTL", "FIP"])
        let regional = try #require(await transport.queryItems(forPath: searchPath).first)
        #expect(regional.contains(URLQueryItem(name: "countrycode", value: "US")))
        #expect(regional.contains(URLQueryItem(name: "order", value: "clickcount")))
        #expect(regional.contains(URLQueryItem(name: "reverse", value: "true")))
    }

    @Test func `a failed regional request falls back to the global list`() async throws {
        let transport = PathRoutingTransport([
            searchPath: .failure(HTTPTransportError.transport("timeout")),
            topClickPath: .success(stationsJSON(["RTL", "FIP"])),
        ])

        let stations = try await client(transport, country: "US").topStations(limit: 5)

        #expect(stations.map(\.name) == ["RTL", "FIP"])
    }

    @Test func `no region means one global request`() async throws {
        let transport = PathRoutingTransport([
            topClickPath: .success(stationsJSON(["RTL", "FIP"])),
        ])

        let stations = try await client(transport, country: nil).topStations(limit: 5)

        #expect(stations.map(\.name) == ["RTL", "FIP"])
        #expect(await transport.requests.count == 1)
    }

    @Test func `a failed global request is still an error`() async throws {
        let transport = PathRoutingTransport([
            searchPath: .success(stationsJSON(["KEXP"])),
            topClickPath: .failure(HTTPTransportError.transport("timeout")),
        ])

        await #expect(throws: RadioDirectoryError.self) {
            _ = try await client(transport, country: "US").topStations(limit: 5)
        }
    }

    // MARK: - Search stays global

    @Test func `search never sends the region`() async throws {
        let transport = PathRoutingTransport([
            searchPath: .success(stationsJSON(["BBC Radio 1"])),
        ])

        _ = try await client(transport, country: "US").searchStations(matching: "BBC", limit: 5)
        _ = try await client(transport, country: "US").stations(inGenre: "jazz", limit: 5)

        let sent = await transport.queryItems(forPath: searchPath)
        #expect(sent.count == 2)
        #expect(sent.allSatisfy { items in items.contains { $0.name == "countrycode" } == false })
    }
}
