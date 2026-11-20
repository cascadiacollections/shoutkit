import Foundation
@testable import RadioDirectory
import Testing

struct StationTagsTests {
    @Test
    func `CSV tags are trimmed and blanks dropped`() {
        #expect(Station.tags(fromCSV: " jazz, ,bebop ,,  swing") == ["jazz", "bebop", "swing"])
    }

    @Test(arguments: [nil, "", " , ,", "\n"] as [String?])
    func `absent or blank CSV is nil`(csv: String?) {
        #expect(Station.tags(fromCSV: csv) == nil)
    }

    @Test
    func `tags serialize to a trimmed CSV`() {
        #expect(Station.tagsCSV(from: [" jazz", "", "bebop "]) == "jazz,bebop")
    }

    @Test(arguments: [nil, [], ["", "  "]] as [[String]?])
    func `absent or blank tags serialize to nil`(tags: [String]?) {
        #expect(Station.tagsCSV(from: tags) == nil)
    }

    @Test
    func `tags round trip through CSV`() {
        let tags = ["jazz", "bebop", "swing"]

        #expect(Station.tags(fromCSV: Station.tagsCSV(from: tags)) == tags)
    }
}

struct StationCodingTests {
    @Test
    func `absent optionals are omitted when encoded`() throws {
        let station = Station(id: "1", name: "Minimal", genre: "Jazz", listenerCount: 3)

        let json = try #require(try String(bytes: JSONEncoder().encode(station), encoding: .utf8))

        for key in ["tags", "country", "codec", "language", "bitrate", "clickTrend", "votes", "artworkURL"] {
            #expect(json.contains("\"\(key)\"") == false, "\(key) should be omitted")
        }
        #expect(json.contains("\"listenerCount\""))
    }

    @Test
    func `full station round trips`() throws {
        let station = Station(
            id: "1",
            name: "Full",
            genre: "Jazz",
            tags: ["bebop"],
            country: "US",
            codec: "AAC",
            language: "english",
            listenerCount: 3,
            bitrate: 128,
            clickTrend: -2,
            votes: 9,
            artworkURL: URL(string: "https://example.com/art.png"),
            preferredStreamURL: URL(string: "https://example.com/live.aac"),
        )

        let decoded = try JSONDecoder().decode(Station.self, from: JSONEncoder().encode(station))

        #expect(decoded == station)
    }
}

struct StreamFormatTests {
    @Test(arguments: [
        ("https://example.com/live.aac", .aac),
        ("https://example.com/live.AAC", .aac),
        ("https://example.com/playlist.m3u8", .hls),
        ("https://example.com/live.mp3", .mp3),
        ("https://example.com/live.mp3?token=abc", .mp3),
        ("https://example.com/live.ogg", .unknown),
        ("https://example.com/live", .unknown),
    ] as [(String, StreamFormat)])
    func `format follows the path extension`(urlString: String, expected: StreamFormat) throws {
        let url = try #require(URL(string: urlString))

        #expect(StreamFormat(url: url) == expected)
    }
}

struct GenreTests {
    @Test
    func `identity is the name`() {
        #expect(Genre(name: "Jazz", stationCount: 4).id == "Jazz")
    }

    @Test
    func `paint time defaults are unique placeholders`() {
        let names = Genre.paintTimeDefaults.map(\.name)

        #expect(names.isEmpty == false)
        #expect(Set(names.map { $0.lowercased() }).count == names.count)
        #expect(Genre.paintTimeDefaults.allSatisfy { $0.stationCount == nil })
        // Capitalised like RadioBrowserDirectoryClient's mapped tag names, so a
        // seeded chip and its live replacement render the same.
        #expect(names.allSatisfy { $0 == $0.capitalized })
    }
}

/// A directory that implements only the requirements without defaults, so the
/// protocol extension's fallbacks are what run.
private struct SearchOnlyDirectory: RadioDirectoryProviding {
    let stations: [Station]

    func genres() async throws(RadioDirectoryError) -> [Genre] {
        []
    }

    func topStations(limit: Int) async throws(RadioDirectoryError) -> [Station] {
        Array(stations.prefix(limit))
    }

    func searchStations(matching query: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        Array(stations.filter { $0.genre.localizedStandardContains(query) }.prefix(limit))
    }

    func streamEndpoint(for _: Station) async throws(RadioDirectoryError) -> StreamEndpoint {
        throw RadioDirectoryError.emptyPlaylist
    }
}

private let jazzStations = [
    Station(id: "low", name: "Low", genre: "Jazz", listenerCount: 0, bitrate: 64),
    Station(id: "mid", name: "Mid", genre: "Jazz", listenerCount: 0, bitrate: 128),
    Station(id: "high", name: "High", genre: "Jazz", listenerCount: 0, bitrate: 320),
    Station(id: "rock", name: "Rock", genre: "Rock", listenerCount: 0, bitrate: 128),
]

struct RadioDirectoryProvidingDefaultsTests {
    @Test
    func `genre query falls back to search`() async throws {
        let directory = SearchOnlyDirectory(stations: jazzStations)

        let stations = try await directory.stations(inGenre: "Jazz", limit: 10)

        #expect(stations.map(\.id) == ["low", "mid", "high"])
    }

    @Test
    func `filtered search drops stations outside the range`() async throws {
        let directory = SearchOnlyDirectory(stations: jazzStations)

        let stations = try await directory.searchStations(
            matching: "Jazz",
            limit: 10,
            filters: StationSearchFilters(bitrateMin: 100),
        )

        #expect(stations.map(\.id) == ["mid", "high"])
    }

    @Test
    func `filtered genre query normalizes an inverted bitrate range`() async throws {
        let directory = SearchOnlyDirectory(stations: jazzStations)

        // min > max normalizes to max = min, so only exactly 128 kbps passes.
        let stations = try await directory.stations(
            inGenre: "Jazz",
            limit: 10,
            filters: StationSearchFilters(bitrateMin: 128, bitrateMax: 64),
        )

        #expect(stations.map(\.id) == ["mid"])
    }

    @Test
    func `default lookup by ID finds nothing`() async throws {
        let directory = SearchOnlyDirectory(stations: jazzStations)

        #expect(try await directory.station(id: "mid") == nil)
    }
}

struct BundledRadioDirectoryTests {
    private let directory = BundledRadioDirectory(stations: jazzStations + [
        Station(id: "jazz-lower", name: "Lower", genre: "jazz", listenerCount: 0),
    ])

    @Test
    func `genres are deduplicated case insensitively in order`() async throws {
        let genres = try await directory.genres()

        #expect(genres.map(\.name) == ["Jazz", "Rock"])
    }

    @Test
    func `blank search returns nothing`() async throws {
        #expect(try await directory.searchStations(matching: "   ", limit: 10).isEmpty)
    }

    @Test
    func `search matches name or genre`() async throws {
        let byName = try await directory.searchStations(matching: "hig", limit: 10)
        let byGenre = try await directory.searchStations(matching: "rock", limit: 10)

        #expect(byName.map(\.id) == ["high"])
        #expect(byGenre.map(\.id) == ["rock"])
    }

    @Test
    func `station without a stream URL is an empty playlist`() async throws {
        await #expect(throws: RadioDirectoryError.emptyPlaylist) {
            try await directory.streamEndpoint(for: jazzStations[0])
        }
    }

    @Test
    func `lookup by ID`() async throws {
        #expect(try await directory.station(id: "rock")?.name == "Rock")
        #expect(try await directory.station(id: "missing") == nil)
    }
}

struct PreviewRadioDirectoryTests {
    private let directory = PreviewRadioDirectory()

    @Test
    func `preview genres carry counts`() async throws {
        let genres = try await directory.genres()

        #expect(genres.isEmpty == false)
        #expect(genres.allSatisfy { $0.stationCount != nil })
    }

    @Test
    func `empty preview search returns nothing`() async throws {
        #expect(try await directory.searchStations(matching: "", limit: 10).isEmpty)
    }

    @Test
    func `preview stream endpoint is a placeholder HLS URL`() async throws {
        let station = try #require(PreviewRadioDirectory.sampleStations.last)

        let endpoint = try await directory.streamEndpoint(for: station)

        #expect(endpoint.format == .hls)
        #expect(endpoint.url.absoluteString == "https://example.com/\(station.id).m3u8")
    }

    @Test
    func `sample station IDs are unique`() {
        let ids = PreviewRadioDirectory.sampleStations.map(\.id)

        #expect(Set(ids).count == ids.count)
    }
}
