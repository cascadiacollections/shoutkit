import Foundation

/// A station launch payload that can round-trip through a deep link for
/// Shortcuts, notifications, promos, or other app-extension entry points.
public struct StationLink: Equatable, Sendable {
    public static let appScheme = "shoutkit"

    public let station: Station
    public let autoPlay: Bool
    public let presentNowPlaying: Bool

    public init(
        station: Station,
        autoPlay: Bool = true,
        presentNowPlaying: Bool = true
    ) {
        self.station = station
        self.autoPlay = autoPlay
        self.presentNowPlaying = presentNowPlaying
    }

    public init?(url: URL, appScheme: String = StationLink.appScheme) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let route = Self.route(from: url, appScheme: appScheme),
              // Accept both a noun (`station`) and a verb (`play`) so promos,
              // notifications, and shortcuts can use whichever reads best.
              route == "station" || route == "play" else {
            return nil
        }

        let items = components.queryItems ?? []
        // Promos/notifications may only know the stream URL. In that case use it
        // as a stable synthetic id so the app can still route and play the target.
        let stationID = Self.value(in: items, named: "id")
            ?? Self.value(in: items, named: "stationID")
            ?? Self.value(in: items, named: "stationId")
            ?? Self.value(in: items, named: "streamURL")
            ?? Self.value(in: items, named: "stream")
            ?? Self.value(in: items, named: "url")
        let name = Self.value(in: items, named: "name")
            ?? Self.value(in: items, named: "title")
            ?? stationID

        guard let stationID, let name else {
            return nil
        }

        let genre = Self.value(in: items, named: "genre") ?? ""
        let listenerCount = Int(Self.value(in: items, named: "listenerCount") ?? "") ?? 0
        let bitrate = Int(Self.value(in: items, named: "bitrate") ?? "")
        let artworkURL = Self.urlValue(in: items, named: ["artworkURL", "artwork"])
        let streamURL = Self.urlValue(in: items, named: ["streamURL", "stream", "url"])

        station = Station(
            id: stationID,
            name: name,
            genre: genre,
            listenerCount: listenerCount,
            bitrate: bitrate,
            artworkURL: artworkURL,
            preferredStreamURL: streamURL
        )
        autoPlay = Self.boolValue(in: items, named: ["autoPlay", "autoplay"], default: true)
        presentNowPlaying = Self.boolValue(
            in: items,
            named: ["presentNowPlaying", "present", "showNowPlaying"],
            default: true
        )
    }

    public func url() -> URL {
        var components = URLComponents()
        components.scheme = StationLink.appScheme
        components.host = "station"
        components.queryItems = queryItems

        guard let url = components.url else {
            preconditionFailure("StationLink produced an invalid shoutkit URL for station '\(station.id)'.")
        }

        return url
    }

    public var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "id", value: station.id),
            URLQueryItem(name: "name", value: station.name),
            URLQueryItem(name: "genre", value: station.genre),
            URLQueryItem(name: "listenerCount", value: String(station.listenerCount)),
            URLQueryItem(name: "autoPlay", value: autoPlay ? "1" : "0"),
            URLQueryItem(name: "presentNowPlaying", value: presentNowPlaying ? "1" : "0")
        ]

        if let bitrate = station.bitrate {
            items.append(URLQueryItem(name: "bitrate", value: String(bitrate)))
        }

        if let artworkURL = station.artworkURL {
            items.append(URLQueryItem(name: "artworkURL", value: artworkURL.absoluteString))
        }

        if let streamURL = station.preferredStreamURL {
            items.append(URLQueryItem(name: "streamURL", value: streamURL.absoluteString))
        }

        return items
    }

    private static func route(from url: URL, appScheme: String) -> String? {
        if url.scheme?.caseInsensitiveCompare(appScheme) == .orderedSame {
            return url.host?.lowercased()
        }

        return url.pathComponents.dropFirst().first?.lowercased()
    }

    private static func value(in items: [URLQueryItem], named name: String) -> String? {
        guard let value = items.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value else {
            return nil
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private static func urlValue(in items: [URLQueryItem], named names: [String]) -> URL? {
        names.lazy
            .compactMap { value(in: items, named: $0) }
            .compactMap(URL.init(string:))
            .first
    }

    private static func boolValue(
        in items: [URLQueryItem],
        named names: [String],
        default defaultValue: Bool
    ) -> Bool {
        for name in names {
            guard let rawValue = value(in: items, named: name)?.lowercased() else {
                continue
            }

            switch rawValue {
            case "0", "false", "no":
                return false
            case "1", "true", "yes":
                return true
            default:
                continue
            }
        }

        return defaultValue
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
