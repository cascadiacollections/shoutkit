import Foundation

/// A station launch payload that can round-trip through an app-scheme deep link
/// for Shortcuts, notifications, promos, or other app-extension entry points.
///
/// Links are untrusted input — any installed app or web page can open one — so
/// the parser accepts only the app scheme, exactly the query items ``url()``
/// emits, and https remote URLs. In-process callers construct the payload
/// directly and never round-trip through a URL.
public struct StationLink: Equatable, Sendable {
    public static let appScheme = "shoutkit"
    public static let handoffActivityType = "com.cascadiacollections.holmdel.station"

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
              components.scheme?.caseInsensitiveCompare(appScheme) == .orderedSame,
              // Accept both a noun (`station`) and a verb (`play`) so promos,
              // notifications, and shortcuts can use whichever reads best.
              let route = components.host?.lowercased(),
              route == "station" || route == "play" else {
            return nil
        }

        let items = components.queryItems ?? []
        let streamURL = Self.httpsURLValue(in: items, named: "streamURL")
        // Promos/notifications may only know the stream URL. In that case use it
        // as a stable synthetic id so the app can still route and play the target.
        let stationID = Self.value(in: items, named: "id") ?? streamURL?.absoluteString
        let name = Self.value(in: items, named: "name") ?? stationID

        guard let stationID, let name else {
            return nil
        }

        station = Station(
            id: stationID,
            name: name,
            genre: Self.value(in: items, named: "genre") ?? "",
            tags: Station.tags(fromCSV: Self.value(in: items, named: "tags")),
            country: Self.value(in: items, named: "country"),
            codec: Self.value(in: items, named: "codec"),
            language: Self.value(in: items, named: "language"),
            listenerCount: Int(Self.value(in: items, named: "listenerCount") ?? "") ?? 0,
            bitrate: Int(Self.value(in: items, named: "bitrate") ?? ""),
            clickTrend: Int(Self.value(in: items, named: "clickTrend") ?? ""),
            votes: Int(Self.value(in: items, named: "votes") ?? ""),
            artworkURL: Self.httpsURLValue(in: items, named: "artworkURL"),
            preferredStreamURL: streamURL
        )
        autoPlay = Self.boolValue(in: items, named: "autoPlay") ?? true
        presentNowPlaying = Self.boolValue(in: items, named: "presentNowPlaying") ?? true
    }

    public func url() -> URL {
        var components = URLComponents()
        components.scheme = StationLink.appScheme
        components.host = "station"
        components.queryItems = queryItems

        guard let url = components.url else {
            // Unreachable in practice: scheme/host are constants and
            // URLComponents percent-encodes query-item values.
            preconditionFailure(
                "StationLink produced an invalid shoutkit URL for station '\(station.id)'. " +
                    "One of the station fields may contain characters that cannot be URL-encoded."
            )
        }

        return url
    }

    public var handoffUserInfo: [String: Any] {
        var userInfo: [String: Any] = [
            HandoffKey.stationID: station.id,
            HandoffKey.autoPlay: autoPlay,
            HandoffKey.presentNowPlaying: presentNowPlaying
        ]

        // Handoff is best-effort: if the snapshot can't be encoded, publish the
        // payload without it — the receiving side treats a snapshot-less payload
        // as non-resumable rather than crashing the publisher.
        do {
            userInfo[HandoffKey.stationSnapshot] = try JSONEncoder().encode(station)
        } catch {
            assertionFailure(
                "Unable to encode station '\(station.id)' for handoff. " +
                    "This indicates Station no longer round-trips through Codable: \(error)"
            )
        }

        return userInfo
    }

    public init?(handoffUserInfo userInfo: [AnyHashable: Any]) {
        guard let stationID = userInfo[HandoffKey.stationID] as? String,
              let stationSnapshot = userInfo[HandoffKey.stationSnapshot] as? Data,
              let station = try? JSONDecoder().decode(Station.self, from: stationSnapshot),
              station.id == stationID else {
            return nil
        }

        self.init(
            station: station,
            autoPlay: userInfo[HandoffKey.autoPlay] as? Bool ?? true,
            presentNowPlaying: userInfo[HandoffKey.presentNowPlaying] as? Bool ?? true
        )
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
            if Self.isHTTPSURL(artworkURL) {
                items.append(URLQueryItem(name: "artworkURL", value: artworkURL.absoluteString))
            }
        }

        if let streamURL = station.preferredStreamURL {
            if Self.isHTTPSURL(streamURL) {
                items.append(URLQueryItem(name: "streamURL", value: streamURL.absoluteString))
            }
        }

        if let tagsCSV = Station.tagsCSV(from: station.tags) {
            items.append(URLQueryItem(name: "tags", value: tagsCSV))
        }

        if let country = station.country {
            items.append(URLQueryItem(name: "country", value: country))
        }

        if let codec = station.codec {
            items.append(URLQueryItem(name: "codec", value: codec))
        }

        if let language = station.language {
            items.append(URLQueryItem(name: "language", value: language))
        }

        if let clickTrend = station.clickTrend {
            items.append(URLQueryItem(name: "clickTrend", value: String(clickTrend)))
        }

        if let votes = station.votes {
            items.append(URLQueryItem(name: "votes", value: String(votes)))
        }

        return items
    }

    private static func value(in items: [URLQueryItem], named name: String) -> String? {
        guard let value = items.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value else {
            return nil
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    /// Remote URLs arriving through a link must be https: a crafted deep link
    /// must not be able to point playback or artwork at cleartext or
    /// local-scheme resources.
    private static func httpsURLValue(in items: [URLQueryItem], named name: String) -> URL? {
        guard let url = value(in: items, named: name).flatMap(URL.init(string:)),
              url.scheme?.caseInsensitiveCompare("https") == .orderedSame else {
            return nil
        }

        return url
    }

    private static func isHTTPSURL(_ url: URL) -> Bool {
        url.scheme?.caseInsensitiveCompare("https") == .orderedSame
    }

    private static func boolValue(in items: [URLQueryItem], named name: String) -> Bool? {
        switch value(in: items, named: name)?.lowercased() {
        case "1", "true":
            return true
        case "0", "false":
            return false
        default:
            return nil
        }
    }
}

private enum HandoffKey {
    static let stationID = "stationID"
    static let stationSnapshot = "stationSnapshot"
    static let autoPlay = "autoPlay"
    static let presentNowPlaying = "presentNowPlaying"
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
