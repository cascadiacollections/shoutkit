import Foundation

// Wire-format DTOs for the Radio-Browser JSON API. Decoding shapes only — the
// mapping onto the domain `Station` lives in
// RadioBrowserDirectoryClient+Mapping.swift.
struct RadioBrowserStation: Decodable {
    let stationuuid: String
    let name: String?
    let url: String?
    let urlResolved: String?
    let favicon: String?
    let tags: String?
    let country: String?
    let codec: String?
    let language: String?
    let bitrate: Int?
    let clickcount: Int?
    let clicktrend: Int?
    let votes: Int?

    enum CodingKeys: String, CodingKey {
        case stationuuid
        case name
        case url
        case urlResolved = "url_resolved"
        case favicon
        case tags
        case country
        case codec
        case language
        case bitrate
        case clickcount
        case clicktrend
        case votes
    }
}

struct RadioBrowserTag: Decodable {
    let name: String
    let stationcount: Int?
}
