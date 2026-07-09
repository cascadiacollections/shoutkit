import Foundation
import RadioDirectory

/// Finds a calm station to offer while an ad break plays. Genre lookups are
/// the best matches, then the broader searches. All of them fan out
/// concurrently — the user is sitting through an ad while this runs — but
/// the winner is still the first hit in priority order. Failed lookups just
/// yield no candidates.
enum AmbientFallbackFinder {
    static let genres = ["Ambient", "Nature"]
    static let queries = ["ambient", "nature", "sleep", "meditation"]

    private enum Lookup: Sendable {
        case genre(String)
        case search(String)
    }

    static func findStation(
        in directory: any RadioDirectoryProviding,
        excluding stationID: Station.ID?
    ) async -> Station? {
        let lookups = genres.map(Lookup.genre) + queries.map(Lookup.search)

        let ranked = await withTaskGroup(of: (Int, [Station]).self) { group in
            for (priority, lookup) in lookups.enumerated() {
                group.addTask {
                    let candidates = await stations(for: lookup, in: directory)
                    return (priority, candidates)
                }
            }

            var collected = Array(repeating: [Station](), count: lookups.count)
            for await (priority, stations) in group {
                collected[priority] = stations
            }
            return collected
        }

        for stations in ranked {
            if let station = stations.first(where: { $0.id != stationID }) {
                return station
            }
        }

        return nil
    }

    private static func stations(
        for lookup: Lookup,
        in directory: any RadioDirectoryProviding
    ) async -> [Station] {
        switch lookup {
        case let .genre(genre):
            (try? await directory.stations(inGenre: genre, limit: 5)) ?? []
        case let .search(query):
            (try? await directory.searchStations(matching: query, limit: 5)) ?? []
        }
    }
}
