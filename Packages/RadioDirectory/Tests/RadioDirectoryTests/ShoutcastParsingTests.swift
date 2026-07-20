import Foundation
import Testing
@testable import RadioDirectory

@Test
func parsesStationXML() throws {
    let xml = """
    <stationlist>
        <station name="Midnight Jazz" id="1234" genre="Jazz" br="192" lc="42" />
    </stationlist>
    """

    let stations = try ShoutcastXMLParser.parseStations(from: Data(xml.utf8))

    #expect(stations == [
        Station(id: "1234", name: "Midnight Jazz", genre: "Jazz", listenerCount: 42, bitrate: 192)
    ])
}

@Test
func parsesGenreXML() throws {
    let xml = """
    <genrelist>
        <genre name="Electronic" count="128" />
    </genrelist>
    """

    let genres = try ShoutcastXMLParser.parseGenres(from: Data(xml.utf8))

    #expect(genres == [
        Genre(name: "Electronic", stationCount: 128)
    ])
}

@Test
func extractsFirstPLSStreamURL() throws {
    let playlist = """
    [playlist]
    NumberOfEntries=2
    File1=http://stream.example.com/live
    Title1=Example Stream
    """

    let url = try PlaylistParser.firstStreamURL(in: playlist)

    #expect(url.absoluteString == "http://stream.example.com/live")
}

@Test
func resolvesRelativePLSStreamURLAgainstPlaylistURL() throws {
    let playlist = """
    [playlist]
    NumberOfEntries=2
    File1=/live
    File2=https://fallback.example.com/live
    """
    let playlistURL = try #require(URL(string: "https://directory.example.com/tunein-station.pls?id=1234"))

    let url = try PlaylistParser.firstStreamURL(in: playlist, playlistURL: playlistURL)

    #expect(url.absoluteString == "https://directory.example.com/live")
}

@Test
func extractsFirstM3UStreamURL() throws {
    let playlist = """
    #EXTM3U
    #EXTINF:-1,Example Stream
    https://stream.example.com/live.m3u8
    """

    let url = try PlaylistParser.firstStreamURL(in: playlist)

    #expect(url.absoluteString == "https://stream.example.com/live.m3u8")
}

@Test
func extractsUppercaseSchemeFromRawM3UFallback() throws {
    let playlist = """
    #EXTM3U
    HTTP://stream.example.com/live.mp3
    """

    let url = try PlaylistParser.firstStreamURL(in: playlist)

    #expect(url.absoluteString.lowercased() == "http://stream.example.com/live.mp3")
}
