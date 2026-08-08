import Foundation
import Testing
@testable import RadioDirectory

private actor FilterRequestRecordingTransport: HTTPTransporting {
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

    func firstRequestQueryItems() -> [URLQueryItem] {
        guard let request = requests.first else { return [] }
        return URLComponents(url: request.url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)?
            .queryItems ?? []
    }
}

struct RadioBrowserSearchFiltersTests {
    @Test
    func searchSendsRadioBrowserFilterParameters() async throws {
        let endpointURL = try #require(URL(string: "https://all.api.radio-browser.info/json/stations/search"))
        let response = try #require(HTTPURLResponse(
            url: endpointURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        let stationJSON = """
        [{
            "stationuuid": "6a7508a9-27ab-11e8-91bf-52543be04c81",
            "name": "KEXP 90.3 Seattle, WA",
            "url": "http://live-mp3-128.kexp.org/kexp128.mp3",
            "url_resolved": "http://live-mp3-128.kexp.org/kexp128.mp3",
            "tags": "jazz",
            "country": "The United States Of America",
            "bitrate": 128
        }]
        """
        let transport = FilterRequestRecordingTransport([.success((Data(stationJSON.utf8), response))])
        let directory = RadioBrowserDirectoryClient(
            transport: transport,
            retryPolicy: RetryPolicy(maximumRetries: 0, timeout: 1, baseDelay: 0)
        )

        _ = try await directory.searchStations(
            matching: "kexp",
            limit: 40,
            filters: StationSearchFilters(bitrateMin: 96, bitrateMax: 192, tag: "jazz", countryCode: "us")
        )

        let queryItems = await transport.firstRequestQueryItems()
        #expect(queryItems.contains(URLQueryItem(name: "bitrateMin", value: "96")))
        #expect(queryItems.contains(URLQueryItem(name: "bitrateMax", value: "192")))
        #expect(queryItems.contains(URLQueryItem(name: "tagList", value: "jazz")))
        #expect(queryItems.contains(URLQueryItem(name: "countrycode", value: "US")))
    }

    @Test
    func genreSearchComposesGenreAndTagFilterAsTagList() async throws {
        let endpointURL = try #require(URL(string: "https://all.api.radio-browser.info/json/stations/search"))
        let response = try #require(HTTPURLResponse(
            url: endpointURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        let stationJSON = """
        [{
            "stationuuid": "6a7508a9-27ab-11e8-91bf-52543be04c81",
            "name": "KEXP 90.3 Seattle, WA",
            "url": "http://live-mp3-128.kexp.org/kexp128.mp3",
            "url_resolved": "http://live-mp3-128.kexp.org/kexp128.mp3",
            "tags": "jazz,live",
            "bitrate": 128
        }]
        """
        let transport = FilterRequestRecordingTransport([.success((Data(stationJSON.utf8), response))])
        let directory = RadioBrowserDirectoryClient(
            transport: transport,
            retryPolicy: RetryPolicy(maximumRetries: 0, timeout: 1, baseDelay: 0)
        )

        _ = try await directory.stations(
            inGenre: "Jazz",
            limit: 40,
            filters: StationSearchFilters(tag: "live")
        )

        let queryItems = await transport.firstRequestQueryItems()
        #expect(queryItems.contains(URLQueryItem(name: "tagList", value: "jazz,live")))
    }
}
