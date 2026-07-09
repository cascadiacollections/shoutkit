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
    func parsesMinimalStationLinks() {
        let url = URL(string: "shoutkit://station?name=KEXP&streamURL=https://example.com/live.mp3")!

        let parsed = StationLink(url: url)

        #expect(parsed?.station.id == "https://example.com/live.mp3")
        #expect(parsed?.station.name == "KEXP")
        #expect(parsed?.station.genre == "")
        #expect(parsed?.station.preferredStreamURL == URL(string: "https://example.com/live.mp3"))
        #expect(parsed?.autoPlay == true)
        #expect(parsed?.presentNowPlaying == true)
    }

    @Test
    func parsesUniversalLinkStyleStationRoutes() {
        let url = URL(string: "https://example.com/station?id=kexp&name=KEXP&autoplay=0&present=0")!

        let parsed = StationLink(url: url)

        #expect(parsed?.station.id == "kexp")
        #expect(parsed?.station.name == "KEXP")
        #expect(parsed?.autoPlay == false)
        #expect(parsed?.presentNowPlaying == false)
    }
}
