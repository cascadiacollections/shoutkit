import Foundation
@testable import RadioDirectory
import Testing

/// Replays queued replies in order and repeats the last one once the queue is
/// down to it, so a retry loop sees the same failure on every attempt.
private actor ScriptedTransport: HTTPTransporting {
    enum Reply: Sendable {
        case status(Int, String)
        case notHTTP
        case failure(any Error & Sendable)
    }

    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let url = request.url ?? URL(fileURLWithPath: "/")
        guard let reply = replies.first else {
            throw HTTPTransportError.transport("No scripted reply")
        }
        if replies.count > 1 {
            replies.removeFirst()
        }

        switch reply {
        case let .status(code, body):
            let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)
            return (Data(body.utf8), response ?? URLResponse())
        case .notHTTP:
            return (Data(), URLResponse())
        case let .failure(error):
            throw error
        }
    }
}

private let endpoints = ShoutcastEndpoints(
    legacyBaseURL: URL(string: "https://directory.example.com/legacy") ?? URL(fileURLWithPath: "/"),
    tuneInBaseURL: URL(string: "https://yp.example.com/sbin/tunein-station.pls") ?? URL(fileURLWithPath: "/"),
)

/// Zero backoff keeps the retry tests instant; two retries is three attempts.
private let instantRetries = RetryPolicy(maximumRetries: 2, timeout: 1, baseDelay: 0)

private let stationListXML = """
<stationlist>
    <station name="Midnight Jazz" id="1" genre="Jazz" br="192" lc="42" />
    <station name="Deep Orbit" id="2" genre="Electronic" br="256" lc="7" />
    <station name="City Signal" id="3" genre="Public Radio" br="128" lc="3" />
</stationlist>
"""

private func makeClient(
    apiKey: String = "test-key",
    transport: ScriptedTransport,
    userAgent: String = "ShoutKitTests/1.0",
) -> ShoutcastDirectoryClient {
    ShoutcastDirectoryClient(
        apiKey: apiKey,
        endpoints: endpoints,
        transport: transport,
        retryPolicy: instantRetries,
        userAgent: userAgent,
    )
}

private func queryItems(of request: URLRequest?) -> [URLQueryItem] {
    guard let url = request?.url else { return [] }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
}

struct ShoutcastDirectoryClientTests {
    // MARK: - Requests

    @Test
    func `genres request carries the key and user agent`() async throws {
        let transport = ScriptedTransport([
            .status(200, #"<genrelist><genre name="Jazz" count="12" /></genrelist>"#),
        ])
        let client = makeClient(transport: transport)

        let genres = try await client.genres()

        #expect(genres == [Genre(name: "Jazz", stationCount: 12)])
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/legacy/genrelist")
        #expect(queryItems(of: request) == [URLQueryItem(name: "k", value: "test-key")])
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "ShoutKitTests/1.0")
    }

    @Test
    func `empty user agent falls back to the default`() async throws {
        let transport = ScriptedTransport([.status(200, "<genrelist />")])
        let client = makeClient(transport: transport, userAgent: "")

        _ = try await client.genres()

        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == RadioBrowserDirectoryClient.defaultUserAgent)
    }

    @Test
    func `top stations respects the limit`() async throws {
        let transport = ScriptedTransport([.status(200, stationListXML)])
        let client = makeClient(transport: transport)

        let stations = try await client.topStations(limit: 2)

        #expect(stations.map(\.id) == ["1", "2"])
        #expect(await transport.requests.first?.url?.path == "/legacy/Top500")
    }

    @Test
    func `search escapes plus so it is not read as a space`() async throws {
        let transport = ScriptedTransport([.status(200, stationListXML)])
        let client = makeClient(transport: transport)

        let stations = try await client.searchStations(matching: "C+C", limit: 10)

        #expect(stations.count == 3)
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/legacy/stationsearch")
        #expect(request.url?.absoluteString.contains("search=C%2BC") == true)
        #expect(queryItems(of: request).first == URLQueryItem(name: "k", value: "test-key"))
    }

    @Test
    func `genre search uses the genre endpoint`() async throws {
        let transport = ScriptedTransport([.status(200, stationListXML)])
        let client = makeClient(transport: transport)

        let stations = try await client.stations(inGenre: "Jazz", limit: 1)

        #expect(stations.map(\.id) == ["1"])
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/legacy/genresearch")
        #expect(queryItems(of: request).contains(URLQueryItem(name: "genre", value: "Jazz")))
    }

    @Test
    func `blank queries return nothing without a request`() async throws {
        let transport = ScriptedTransport([.status(200, stationListXML)])
        let client = makeClient(transport: transport)

        let search = try await client.searchStations(matching: "  \n", limit: 10)
        let genre = try await client.stations(inGenre: " ", limit: 10)

        #expect(search.isEmpty)
        #expect(genre.isEmpty)
        #expect(await transport.requests.isEmpty)
    }

    // MARK: - API key

    @Test
    func `missing key fails before any request`() async throws {
        let transport = ScriptedTransport([.status(200, stationListXML)])
        let client = makeClient(apiKey: "   ", transport: transport)

        await #expect(throws: RadioDirectoryError.missingAPIKey) {
            try await client.topStations(limit: 10)
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test
    func `tune in resolves without a key`() async throws {
        let playlist = """
        [playlist]
        NumberOfEntries=1
        File1=/stream/live.mp3
        """
        let transport = ScriptedTransport([.status(200, playlist)])
        let client = makeClient(apiKey: "", transport: transport)
        let station = Station(id: "1234", name: "Midnight Jazz", genre: "Jazz", listenerCount: 0)

        let endpoint = try await client.streamEndpoint(for: station)

        #expect(endpoint.stationID == "1234")
        #expect(endpoint.url.absoluteString == "https://yp.example.com/stream/live.mp3")
        #expect(endpoint.format == .mp3)
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/sbin/tunein-station.pls")
        #expect(queryItems(of: request) == [URLQueryItem(name: "id", value: "1234")])
    }

    @Test
    func `tune in with no stream is an empty playlist`() async throws {
        let transport = ScriptedTransport([.status(200, "[playlist]\nNumberOfEntries=0\n")])
        let client = makeClient(transport: transport)
        let station = Station(id: "1234", name: "Silent", genre: "Jazz", listenerCount: 0)

        await #expect(throws: RadioDirectoryError.emptyPlaylist) {
            try await client.streamEndpoint(for: station)
        }
    }

    // MARK: - Failures

    @Test
    func `transient server error is retried`() async throws {
        let transport = ScriptedTransport([
            .status(503, ""),
            .status(200, stationListXML),
        ])
        let client = makeClient(transport: transport)

        let stations = try await client.topStations(limit: 10)

        #expect(stations.count == 3)
        #expect(await transport.requests.count == 2)
    }

    @Test
    func `persistent server error surfaces its status after the retry budget`() async throws {
        let transport = ScriptedTransport([.status(503, "")])
        let client = makeClient(transport: transport)

        await #expect(throws: RadioDirectoryError.httpStatus(503)) {
            try await client.genres()
        }
        #expect(await transport.requests.count == instantRetries.maximumRetries + 1)
    }

    @Test
    func `non HTTP response maps to invalid response`() async throws {
        let transport = ScriptedTransport([.notHTTP])
        let client = makeClient(transport: transport)

        await #expect(throws: RadioDirectoryError.invalidResponse) {
            try await client.genres()
        }
    }

    @Test
    func `transport error keeps its message`() async throws {
        let transport = ScriptedTransport([.failure(HTTPTransportError.transport("offline"))])
        let client = makeClient(transport: transport)

        await #expect(throws: RadioDirectoryError.transport("offline")) {
            try await client.genres()
        }
    }

    @Test
    func `foreign error maps to transport with its description`() async throws {
        let underlying = URLError(.notConnectedToInternet)
        let transport = ScriptedTransport([.failure(underlying)])
        let client = makeClient(transport: transport)

        await #expect(throws: RadioDirectoryError.transport(underlying.localizedDescription)) {
            try await client.genres()
        }
    }

    @Test
    func `malformed XML is a parsing failure and is not retried`() async throws {
        let transport = ScriptedTransport([.status(200, "<stationlist><station")])
        let client = makeClient(transport: transport)

        let error = await #expect(throws: RadioDirectoryError.self) {
            try await client.topStations(limit: 10)
        }

        guard case .parsingFailed = error else {
            Issue.record("Expected parsingFailed, got \(String(describing: error))")
            return
        }
        #expect(await transport.requests.count == 1)
    }
}

struct ShoutcastEndpointsTests {
    @Test
    func `legacy URL puts the key first`() throws {
        let url = try endpoints.legacyURL(
            endpoint: "stationsearch",
            apiKey: "abc",
            queryItems: [URLQueryItem(name: "search", value: "jazz")],
        )

        #expect(url.absoluteString == "https://directory.example.com/legacy/stationsearch?k=abc&search=jazz")
    }

    @Test
    func `tune in URL carries the station id`() {
        let url = endpoints.tuneInURL(stationID: "99")

        #expect(url.absoluteString == "https://yp.example.com/sbin/tunein-station.pls?id=99")
    }

    @Test
    func `production endpoints point at SHOUTcast`() {
        #expect(ShoutcastEndpoints.production.legacyBaseURL.host == "api.shoutcast.com")
        #expect(ShoutcastEndpoints.production.tuneInBaseURL.host == "yp.shoutcast.com")
    }
}
