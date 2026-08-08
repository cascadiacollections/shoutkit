import Testing
@testable import RadioDirectory

struct StationSearchFiltersTests {
    @Test
    func bitrateFilterDoesNotExcludeUnknownBitrates() {
        let filters = StationSearchFilters(bitrateMin: 128)
        let unknownBitrate = Station(id: "a", name: "Unknown", genre: "Jazz", listenerCount: 0)
        let lowBitrate = Station(id: "b", name: "Low", genre: "Jazz", listenerCount: 0, bitrate: 64)

        #expect(filters.matches(unknownBitrate))
        #expect(filters.matches(lowBitrate) == false)
    }

    @Test
    func countryFilterDoesNotExcludeMissingCountry() {
        let filters = StationSearchFilters(countryCode: "us")
        let missingCountry = Station(id: "a", name: "Unknown", genre: "Jazz", listenerCount: 0)
        let mismatchedCountry = Station(id: "b", name: "Mismatch", genre: "Jazz", country: "France", listenerCount: 0)

        #expect(filters.matches(missingCountry))
        #expect(filters.matches(mismatchedCountry) == false)
    }
}
