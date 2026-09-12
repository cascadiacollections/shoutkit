@testable import RadioDirectory
import Testing

struct StationSearchFiltersTests {
    @Test
    func `bitrate filter does not exclude unknown bitrates`() {
        let filters = StationSearchFilters(bitrateMin: 128)
        let unknownBitrate = Station(id: "a", name: "Unknown", genre: "Jazz", listenerCount: 0)
        let lowBitrate = Station(id: "b", name: "Low", genre: "Jazz", listenerCount: 0, bitrate: 64)

        #expect(filters.matches(unknownBitrate))
        #expect(filters.matches(lowBitrate) == false)
    }

    @Test
    func `country filter does not exclude missing country`() {
        let filters = StationSearchFilters(countryCode: "us")
        let missingCountry = Station(id: "a", name: "Unknown", genre: "Jazz", listenerCount: 0)
        let mismatchedCountry = Station(id: "b", name: "Mismatch", genre: "Jazz", country: "France", listenerCount: 0)

        #expect(filters.matches(missingCountry))
        #expect(filters.matches(mismatchedCountry) == false)
    }
}
