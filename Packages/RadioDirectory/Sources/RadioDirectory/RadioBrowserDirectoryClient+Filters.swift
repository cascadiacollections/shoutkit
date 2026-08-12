import Foundation

// Encodes `StationSearchFilters` as Radio-Browser query parameters. Internal
// rather than `private` now that it lives beside the client rather than inside
// its file; nothing outside this module names it.
extension StationSearchFilters {
    func radioBrowserQueryItems(excludingTag: Bool = false) -> [URLQueryItem] {
        var queryItems: [URLQueryItem] = []

        if let bitrateMin {
            queryItems.append(URLQueryItem(name: "bitrateMin", value: String(bitrateMin)))
        }
        if let bitrateMax {
            queryItems.append(URLQueryItem(name: "bitrateMax", value: String(bitrateMax)))
        }
        if excludingTag == false, let tag {
            queryItems.append(URLQueryItem(name: "tagList", value: tag.lowercased()))
        }
        if let countryCode {
            queryItems.append(URLQueryItem(name: "countrycode", value: countryCode))
        }

        return queryItems
    }
}
