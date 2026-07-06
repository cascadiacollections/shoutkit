import Foundation
import Testing
@testable import RadioDirectory

private func decodeStations(_ json: String) throws -> [RadioBrowserStation] {
    try JSONDecoder().decode([RadioBrowserStation].self, from: Data(json.utf8))
}

@Test
func decodesRadioBrowserStationJSON() throws {
    let json = """
    [{
        "stationuuid": "6a7508a9-27ab-11e8-91bf-52543be04c81",
        "name": "KEXP 90.3 Seattle, WA",
        "url": "http://live-mp3-128.kexp.org/kexp128.mp3",
        "url_resolved": "http://live-mp3-128.kexp.org/kexp128.mp3",
        "favicon": "http://www.kexp.org/static/assets/img/favicon-32x32.png",
        "tags": "alternative rock,indie,live",
        "country": "The United States Of America",
        "codec": "MP3",
        "bitrate": 128,
        "clickcount": 26
    }]
    """

    let stations = try decodeStations(json).compactMap(RadioBrowserDirectoryClient.station(from:))

    #expect(stations.count == 1)
    let station = try #require(stations.first)
    #expect(station.id == "6a7508a9-27ab-11e8-91bf-52543be04c81")
    #expect(station.name == "KEXP 90.3 Seattle, WA")
    #expect(station.genre == "Alternative Rock")
    #expect(station.bitrate == 128)
    #expect(station.preferredStreamURL?.absoluteString == "http://live-mp3-128.kexp.org/kexp128.mp3")
}

@Test
func fallsBackToRawURLWhenResolvedIsEmpty() throws {
    let json = """
    [{
        "stationuuid": "445cbb3a-1c4e-49aa-a268-f5b6acfa8f2e",
        "name": "Fallback FM",
        "url": "https://stream.example.com/live.aac",
        "url_resolved": "",
        "tags": "",
        "bitrate": 0
    }]
    """

    let station = try #require(decodeStations(json).compactMap(RadioBrowserDirectoryClient.station(from:)).first)

    #expect(station.preferredStreamURL?.absoluteString == "https://stream.example.com/live.aac")
    // bitrate 0 means "unknown" in Radio-Browser, not zero kbps.
    #expect(station.bitrate == nil)
}

@Test
func dropsStationsWithoutNameOrStreamURL() throws {
    let json = """
    [
        {"stationuuid": "a", "name": "  ", "url": "https://stream.example.com/a"},
        {"stationuuid": "b", "name": "No Stream", "url": "", "url_resolved": ""},
        {"stationuuid": "c", "name": "Keeper", "url": "https://stream.example.com/c"}
    ]
    """

    let stations = try decodeStations(json).compactMap(RadioBrowserDirectoryClient.station(from:))

    #expect(stations.map(\.name) == ["Keeper"])
}

@Test
func genreFallsBackToCountryThenPlaceholder() throws {
    let json = """
    [
        {"stationuuid":"a","name":"Tagged","url":"https://x.example/a","tags":"jazz,smooth","country":"France"},
        {"stationuuid":"b","name":"Country Only","url":"https://x.example/b","tags":"","country":"France"},
        {"stationuuid":"c","name":"Bare","url":"https://x.example/c"}
    ]
    """

    let stations = try decodeStations(json).compactMap(RadioBrowserDirectoryClient.station(from:))

    #expect(stations.map(\.genre) == ["Jazz", "France", "Radio"])
}

@Test
func upgradesInsecureFaviconsAndDropsEmptyOnes() {
    #expect(
        RadioBrowserDirectoryClient.artworkURL(from: "http://example.com/icon.png")?.absoluteString
            == "https://example.com/icon.png"
    )
    #expect(
        RadioBrowserDirectoryClient.artworkURL(from: "https://example.com/icon.png")?.absoluteString
            == "https://example.com/icon.png"
    )
    #expect(RadioBrowserDirectoryClient.artworkURL(from: "") == nil)
    #expect(RadioBrowserDirectoryClient.artworkURL(from: nil) == nil)
}

@Test
func decodesTagListIntoGenres() throws {
    let json = """
    [{"name": "pop", "stationcount": 5767}, {"name": "  ", "stationcount": 3}]
    """

    let tags = try JSONDecoder().decode([RadioBrowserTag].self, from: Data(json.utf8))

    #expect(tags.count == 2)
    #expect(tags[0].name == "pop")
    #expect(tags[0].stationcount == 5767)
}
