import Foundation
import Testing
@testable import RadioDirectory

struct StationLinkTests {
    @Test
    func roundTripsShoutKitStationURL() {
        let station = Station(
            id: "npr-newscast",
            name: "NPR News Now",
            genre: "News",
            listenerCount: 42,
            bitrate: 128,
            artworkURL: URL(string: "https://example.com/artwork.png"),
            preferredStreamURL: URL(string: "https://example.com/live.mp3")
        )
        let link = StationLink(station: station, autoPlay: true, presentNowPlaying: false)

        let parsed = StationLink(url: link.url())

        #expect(parsed == link)
    }

    @Test
    func parsesMinimalStationLinks() throws {
        let url = try #require(URL(string: "shoutkit://station?name=KEXP&streamURL=https://example.com/live.mp3"))

        let parsed = StationLink(url: url)

        #expect(parsed?.station.id == "https://example.com/live.mp3")
        #expect(parsed?.station.name == "KEXP")
        #expect(parsed?.station.genre == "")
        #expect(parsed?.station.preferredStreamURL == URL(string: "https://example.com/live.mp3"))
        #expect(parsed?.autoPlay == true)
        #expect(parsed?.presentNowPlaying == true)
    }

    @Test
    func parsesPlayRouteWithExplicitFlags() throws {
        let url = try #require(URL(string: "shoutkit://play?id=kexp&name=KEXP&autoPlay=0&presentNowPlaying=false"))

        let parsed = StationLink(url: url)

        #expect(parsed?.station.id == "kexp")
        #expect(parsed?.autoPlay == false)
        #expect(parsed?.presentNowPlaying == false)
    }

    @Test(arguments: [
        // Only the registered app scheme routes; universal-link-style URLs are
        // not configured (no associated domains) and must not parse.
        "https://example.com/station?id=kexp&name=KEXP",
        "file:///station?id=kexp&name=KEXP",
        // Unknown route hosts must not parse.
        "shoutkit://settings?id=kexp&name=KEXP",
        // A station identified only by a cleartext stream URL has no usable
        // id or playable stream, so the whole link is rejected.
        "shoutkit://station?name=KEXP&streamURL=http://example.com/live.mp3",
        // No id and no name.
        "shoutkit://station?genre=News"
    ])
    func rejectsUntrustedOrMalformedLinks(urlString: String) throws {
        let url = try #require(URL(string: urlString))

        #expect(StationLink(url: url) == nil)
    }

    @Test
    func dropsCleartextRemoteURLsButKeepsIdentifiedStation() throws {
        let url = try #require(URL(
            string: "shoutkit://station?id=kexp&streamURL=http://x.example/s.mp3&artworkURL=http://x.example/a.png"
        ))

        let parsed = StationLink(url: url)

        #expect(parsed?.station.id == "kexp")
        #expect(parsed?.station.preferredStreamURL == nil)
        #expect(parsed?.station.artworkURL == nil)
    }

    @Test
    func roundTripsHandoffUserInfo() {
        let station = Station(
            id: "kexp",
            name: "KEXP",
            genre: "Indie",
            tags: ["Seattle", "Alternative"],
            country: "US",
            codec: "mp3",
            language: "en",
            listenerCount: 1_234,
            bitrate: 128,
            clickTrend: 9,
            votes: 88,
            artworkURL: URL(string: "https://example.com/artwork.png"),
            preferredStreamURL: URL(string: "https://example.com/live.mp3")
        )
        let link = StationLink(station: station, autoPlay: false, presentNowPlaying: true)

        let parsed = StationLink(handoffUserInfo: link.handoffUserInfo)

        #expect(parsed == link)
    }

    @Test
    func rejectsHandoffUserInfoWithMismatchedStationID() throws {
        let station = Station(
            id: "kexp",
            name: "KEXP",
            genre: "Indie",
            listenerCount: 1,
            preferredStreamURL: URL(string: "https://example.com/live.mp3")
        )
        let link = StationLink(station: station)
        var userInfo = link.handoffUserInfo
        userInfo["stationID"] = "kcrw"

        #expect(StationLink(handoffUserInfo: userInfo) == nil)
    }
}
