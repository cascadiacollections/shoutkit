import Foundation
import RadioDirectory
import Testing

@testable import DesignSystem

struct AlbumArtLookupTests {
    @Test
    func buildSearchURLIncludesExpectedQueryItems() throws {
        let url = try #require(AlbumArtLookup.buildSearchURL(
            artist: "Florence + The Machine",
            title: "Dog Days Are Over",
            regionIdentifier: "GB"
        ))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(
            uniqueKeysWithValues: try #require(components.queryItems).map { ($0.name, $0.value ?? "") }
        )

        #expect(components.scheme == "https")
        #expect(components.host == "itunes.apple.com")
        #expect(components.path == "/search")
        #expect(queryItems["term"] == "Florence + The Machine Dog Days Are Over")
        #expect(queryItems["media"] == "music")
        #expect(queryItems["entity"] == "song")
        #expect(queryItems["limit"] == "1")
        #expect(queryItems["country"] == "GB")
        #expect(components.percentEncodedQuery?.contains("%2B") == true)
    }

    @Test
    func buildSearchURLOmitsCountryWhenRegionUnavailable() throws {
        let url = try #require(AlbumArtLookup.buildSearchURL(
            artist: "Artist",
            title: "Title",
            regionIdentifier: nil
        ))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryNames = Set(try #require(components.queryItems).map(\.name))
        #expect(queryNames.contains("country") == false)
    }

    struct UpsizeCase: Sendable {
        let source: String?
        let expected: String?
    }

    @Test(arguments: [
        UpsizeCase(
            source: "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/x/y/z/100x100bb.jpg",
            expected: "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/x/y/z/600x600bb.jpg"
        ),
        UpsizeCase(
            source: "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/x/y/z/300x300bb.jpg",
            expected: "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/x/y/z/300x300bb.jpg"
        ),
        UpsizeCase(source: nil, expected: nil),
        UpsizeCase(source: "not a url", expected: nil)
    ])
    func artworkURLUpsizingIsDeterministic(testCase: UpsizeCase) {
        #expect(AlbumArtLookup.upsizedArtworkURL(from: testCase.source)?.absoluteString == testCase.expected)
    }

    @Test
    func lookupCacheSeparatesStorefronts() async throws {
        let transport = StubLookupTransport { request in
            guard let requestURL = request.url else { throw URLError(.badURL) }
            let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)
            let country = components?.queryItems?.first(where: { $0.name == "country" })?.value ?? ""
            switch country {
            case "US":
                return Self.makeLookupResponseData(
                    artwork: "https://is1-ssl.mzstatic.com/image/thumb/Music123/v4/us/100x100bb.jpg",
                    link: "https://music.apple.com/us/song/us-song/1"
                )
            case "GB":
                return Self.makeLookupResponseData(
                    artwork: "https://is1-ssl.mzstatic.com/image/thumb/Music123/v4/gb/100x100bb.jpg",
                    link: "https://music.apple.com/gb/song/gb-song/2"
                )
            default:
                return Self.makeLookupResponseData(
                    artwork: "https://is1-ssl.mzstatic.com/image/thumb/Music123/v4/default/100x100bb.jpg",
                    link: "https://music.apple.com/song/default-song/3"
                )
            }
        }

        let artist = "Storefront Artist \(UUID().uuidString)"
        let title = "Storefront Track \(UUID().uuidString)"
        let usResult = await AlbumArtLookup.lookup(
            artist: artist,
            title: title,
            regionIdentifier: "US",
            transport: transport
        )
        let gbResult = await AlbumArtLookup.lookup(
            artist: artist,
            title: title,
            regionIdentifier: "GB",
            transport: transport
        )
        let usCached = await AlbumArtLookup.lookup(
            artist: artist,
            title: title,
            regionIdentifier: "US",
            transport: transport
        )

        #expect(usResult == usCached)
        #expect(usResult != gbResult)
        #expect(await transport.requestCount == 2)
    }

    @Test
    func lookupCoalescesConcurrentRequestsForSameStorefront() async throws {
        let transport = StubLookupTransport { _ in
            try await Task.sleep(for: .milliseconds(100))
            return Self.makeLookupResponseData(
                artwork: "https://is1-ssl.mzstatic.com/image/thumb/Music123/v4/inflight/100x100bb.jpg",
                link: "https://music.apple.com/us/song/inflight-song/4"
            )
        }

        let artist = "InFlight Artist \(UUID().uuidString)"
        let title = "InFlight Track \(UUID().uuidString)"
        async let first = AlbumArtLookup.lookup(
            artist: artist,
            title: title,
            regionIdentifier: "US",
            transport: transport
        )
        async let second = AlbumArtLookup.lookup(
            artist: artist,
            title: title,
            regionIdentifier: "US",
            transport: transport
        )
        let firstMatch = await first
        let secondMatch = await second

        #expect(firstMatch == secondMatch)
        #expect(await transport.requestCount == 1)
    }

    private actor StubLookupTransport: HTTPTransporting {
        // swiftlint:disable:next nesting
        typealias Responder = @Sendable (URLRequest) async throws -> Data

        private let responder: Responder
        private(set) var requestCount = 0

        init(_ responder: @escaping Responder) {
            self.responder = responder
        }

        func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
            requestCount += 1
            let data = try await responder(request)
            guard let url = request.url else { throw URLError(.badURL) }
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ) else { throw URLError(.badServerResponse) }
            return (data, response)
        }
    }

    private static func makeLookupResponseData(artwork: String, link: String) -> Data {
        Data("""
        {"results":[{"artworkUrl100":"\(artwork)","trackViewUrl":"\(link)"}]}
        """.utf8)
    }
}
