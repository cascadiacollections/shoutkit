import Foundation
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
        let queryItems = Dictionary(uniqueKeysWithValues: try #require(components.queryItems).map { ($0.name, $0.value ?? "") })

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
}
