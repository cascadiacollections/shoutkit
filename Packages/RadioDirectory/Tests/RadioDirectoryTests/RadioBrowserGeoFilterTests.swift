import Foundation
@testable import RadioDirectory
import Testing

private actor RequestRecordingTransport: HTTPTransporting {
    private(set) var requests: [URLRequest] = []
    private var results: [Result<(Data, URLResponse), Error>]

    init(_ results: [Result<(Data, URLResponse), Error>]) {
        self.results = results
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard results.isEmpty == false else {
            throw HTTPTransportError.transport("No queued response")
        }
        return try results.removeFirst().get()
    }

    func requestedQueryItems() -> [[URLQueryItem]] {
        requests.compactMap { request in
            URLComponents(
                url: request.url ?? URL(fileURLWithPath: "/"),
                resolvingAgainstBaseURL: false,
            )?.queryItems
        }
    }
}

private struct StaticGeoFilterProvider: RadioBrowserGeoFilterProviding {
    let geoFilter: RadioBrowserGeoFilter?

    func currentGeoFilter() async -> RadioBrowserGeoFilter? {
        geoFilter
    }
}

struct RadioBrowserGeoFilterTests {
    @Test
    func `locale filter prefers region and falls back to language`() {
        let locale = Locale(identifier: "en_US")
        let filter = RadioBrowserGeoFilter(locale: locale)

        #expect(filter.countryCode == "US")
        #expect(filter.languageCode == "en")
        #expect(
            filter.queryItemSets.map { $0.first?.name } == ["countrycode", "language"],
        )
        #expect(
            filter.queryItemSets.map { $0.first?.value } == ["US", "en"],
        )
    }

    @Test
    func `locale filter can use geocoded country override`() {
        let locale = Locale(identifier: "fr_CA")
        let filter = RadioBrowserGeoFilter(locale: locale, countryCodeOverride: "US")

        #expect(filter.countryCode == "US")
        #expect(filter.languageCode == "fr")
        #expect(
            filter.queryItemSets.map { $0.first?.value } == ["US", "fr"],
        )
    }

    @Test
    func `locale filter drops empty components`() {
        let filter = RadioBrowserGeoFilter(countryCode: "  ", languageCode: "\n")

        #expect(filter.countryCode == nil)
        #expect(filter.languageCode == nil)
        #expect(filter.queryItemSets == [[]])
    }

    @Test
    func `mutable provider returns latest filter`() async {
        let provider = MutableRadioBrowserGeoFilterProvider()
        #expect(await provider.currentGeoFilter() == nil)

        let geoFilter = RadioBrowserGeoFilter(countryCode: "CA", languageCode: "en")
        await provider.setCurrentGeoFilter(geoFilter)

        #expect(await provider.currentGeoFilter() == geoFilter)
    }

    @Test
    func `directory falls back from country to language query`() async throws {
        let endpointURL = try #require(URL(string: "https://all.api.radio-browser.info/json/stations/topclick"))
        let response = try #require(HTTPURLResponse(
            url: endpointURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil,
        ))
        let stationJSON = """
        [{
            "stationuuid": "6a7508a9-27ab-11e8-91bf-52543be04c81",
            "name": "KEXP 90.3 Seattle, WA",
            "url": "http://live-mp3-128.kexp.org/kexp128.mp3",
            "url_resolved": "http://live-mp3-128.kexp.org/kexp128.mp3",
            "tags": "alternative rock,indie,live",
            "bitrate": 128
        }]
        """
        let transport = RequestRecordingTransport([
            .success((Data("[]".utf8), response)),
            .success((Data(stationJSON.utf8), response)),
        ])
        let provider = StaticGeoFilterProvider(
            geoFilter: RadioBrowserGeoFilter(countryCode: "US", languageCode: "en"),
        )
        let directory = RadioBrowserDirectoryClient(
            transport: transport,
            retryPolicy: RetryPolicy(maximumRetries: 0, timeout: 1, baseDelay: 0),
            geoFilterProvider: provider,
        )

        let stations = try await directory.topStations(limit: 5)

        #expect(stations.map(\.name) == ["KEXP 90.3 Seattle, WA"])
        let queryItems = await transport.requestedQueryItems()
        #expect(queryItems.count == 2)
        #expect(queryItems[0].contains(URLQueryItem(name: "countrycode", value: "US")))
        #expect(queryItems[1].contains(URLQueryItem(name: "language", value: "en")))
    }

    @Test
    func `directory falls back to language when country query errors`() async throws {
        let endpointURL = try #require(URL(string: "https://all.api.radio-browser.info/json/stations/topclick"))
        let response = try #require(HTTPURLResponse(
            url: endpointURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil,
        ))
        let stationJSON = """
        [{
            "stationuuid": "6a7508a9-27ab-11e8-91bf-52543be04c81",
            "name": "KEXP 90.3 Seattle, WA",
            "url": "http://live-mp3-128.kexp.org/kexp128.mp3",
            "url_resolved": "http://live-mp3-128.kexp.org/kexp128.mp3",
            "bitrate": 128
        }]
        """
        let transport = RequestRecordingTransport([
            .failure(HTTPTransportError.transport("timeout")),
            .success((Data(stationJSON.utf8), response)),
        ])
        let provider = StaticGeoFilterProvider(
            geoFilter: RadioBrowserGeoFilter(countryCode: "US", languageCode: "en"),
        )
        let directory = RadioBrowserDirectoryClient(
            transport: transport,
            retryPolicy: RetryPolicy(maximumRetries: 0, timeout: 1, baseDelay: 0),
            geoFilterProvider: provider,
        )

        let stations = try await directory.topStations(limit: 5)

        #expect(stations.map(\.name) == ["KEXP 90.3 Seattle, WA"])
        let queryItems = await transport.requestedQueryItems()
        #expect(queryItems.count == 2)
        #expect(queryItems[0].contains(URLQueryItem(name: "countrycode", value: "US")))
        #expect(queryItems[1].contains(URLQueryItem(name: "language", value: "en")))
    }
}
