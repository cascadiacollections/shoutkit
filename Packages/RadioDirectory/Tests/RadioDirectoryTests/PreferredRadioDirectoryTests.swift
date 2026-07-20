import Testing
@testable import RadioDirectory

@Test
func preferredStationsLeadTopStations() async throws {
    let directory = PreferredRadioDirectory(base: PreviewRadioDirectory())

    let stations = try await directory.topStations(limit: 4)

    #expect(stations.first?.name == "KEXP 90.3 FM")
    #expect(stations.map(\.id).contains("preferred-kexp-64-aac"))
}

@Test
func preferredKEXPResolvesDirectStreamURL() async throws {
    let directory = PreferredRadioDirectory(base: PreviewRadioDirectory())

    let endpoint = try await directory.streamEndpoint(for: PreferredStations.kexpHighBandwidth)

    #expect(endpoint.url.absoluteString == "https://kexp.streamguys1.com/kexp160.aac")
    #expect(endpoint.format == .aac)
}

@Test
func preferredSearchFindsKEXP() async throws {
    let directory = PreferredRadioDirectory(base: PreviewRadioDirectory())

    let stations = try await directory.searchStations(matching: "kexp", limit: 10)

    #expect(stations.map(\.id) == ["preferred-kexp-160-aac", "preferred-kexp-64-aac"])
}

@Test
func preferredGenreQueryForwardsToBaseAndLayersMatches() async throws {
    let directory = PreferredRadioDirectory(base: PreviewRadioDirectory())

    // Preview's genre fallback is a search, which matches its sample stations'
    // genre field; no preferred station is in this genre.
    let electronic = try await directory.stations(inGenre: "Electronic", limit: 10)
    #expect(electronic.map(\.id) == ["ambient-current", "deep-orbit"])

    // Preferred stations whose genre matches lead the results.
    let indie = try await directory.stations(inGenre: "Indie", limit: 10)
    #expect(indie.first?.id == "preferred-kexp-160-aac")
}

@Test
func stationLookupByIDFindsPreferredThenFallsBackToBase() async throws {
    let directory = PreferredRadioDirectory(base: PreviewRadioDirectory())

    let preferred = try await directory.station(id: "preferred-kexp-160-aac")
    let base = try await directory.station(id: "ambient-current")
    let missing = try await directory.station(id: "missing")

    #expect(preferred?.name == "KEXP 90.3 FM")
    #expect(base?.name == "Ambient Current")
    #expect(missing == nil)
}

@Test
func bundledDirectoryContainsOnlyCuratedLiveStations() async throws {
    let directory = BundledRadioDirectory()

    let stations = try await directory.topStations(limit: 10)

    #expect(stations.map(\.id) == ["preferred-kexp-160-aac", "preferred-kexp-64-aac"])
}

@Test
func bundledDirectoryResolvesKEXPWithoutShoutcastKey() async throws {
    let directory = BundledRadioDirectory()

    let endpoint = try await directory.streamEndpoint(for: PreferredStations.kexpLowBandwidth)

    #expect(endpoint.url.absoluteString == "https://kexp.streamguys1.com/kexp64.aac")
    #expect(endpoint.format == .aac)
}
