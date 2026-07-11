import Foundation
import os

/// Best-effort track discovery via the public iTunes Search API.
///
/// A single query yields both high-quality album artwork and a link to open
/// the exact matched song in Apple Music (`trackViewUrl`) — so callers get
/// both from one network hit. Queries are session-cached so repeated lookups
/// for the same artist/title don't leave the app's sandbox. The service is
/// deliberately simple — one hit per track, empty on any failure — to stay
/// true to the "best effort" contract callers expect.
///
/// `nonisolated` opts the whole type out of the package's main-actor default:
/// this is pure networking with `Sendable` shared state (session + locked
/// cache), and lookups must not tie up the main actor.
public nonisolated enum AlbumArtLookup {
    /// The resolved catalog entry for a track. Both fields are independently
    /// optional: the catalog may have artwork but no linkable store page, or
    /// (rarely) the reverse. An all-`nil` value means "no usable match".
    public struct Match: Sendable, Equatable {
        /// High-quality (up to 600 × 600) album artwork, or `nil`.
        public let artworkURL: URL?
        /// A link that opens the song in Apple Music (or its web player when
        /// the app isn't installed), or `nil` when the catalog has no page.
        public let appleMusicURL: URL?

        public init(artworkURL: URL? = nil, appleMusicURL: URL? = nil) {
            self.artworkURL = artworkURL
            self.appleMusicURL = appleMusicURL
        }

        /// A match carrying neither artwork nor a store link.
        static let empty = Match()
    }

    /// Shared URL session configured with a short timeout; artwork is a
    /// nicety, not a requirement, so we fail fast rather than block the UI.
    private static let requestTimeout: TimeInterval = 8
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        return URLSession(configuration: config)
    }()

    /// In-process lookup cache, keyed on "artist|title" (lowercased). Caches
    /// both hits and definitive misses — a track the catalog simply doesn't
    /// have would otherwise re-query iTunes on every ICY repeat, which over a
    /// long background listening session is pure network/battery waste.
    /// Transient failures (transport error, non-200, malformed payload) are
    /// still NOT cached, so a network blip doesn't permanently suppress art.
    private enum CachedLookup {
        case match(Match)
        case noMatch
    }

    /// Values are tiny, but a multi-day session shouldn't grow unbounded:
    /// past the cap the cache is simply reset (a rare full re-warm is cheaper
    /// than LRU bookkeeping on every lookup).
    private static let maxCacheEntries = 256

    private static let cache = OSAllocatedUnfairLock<[String: CachedLookup]>(initialState: [:])

    /// Resolves artwork and an Apple Music link for the given artist and title.
    ///
    /// - Parameters:
    ///   - artist: The performing artist.
    ///   - title:  The track title.
    /// - Returns: A ``Match`` carrying the artwork URL (up to 600 × 600 points)
    ///   and/or the Apple Music link. Returns an empty `Match` (both fields
    ///   `nil`) when either parameter is absent/empty or when the lookup fails.
    public static func lookup(artist: String?, title: String?) async -> Match {
        guard let artist = artist?.trimmingCharacters(in: .whitespacesAndNewlines),
              let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              artist.isEmpty == false, title.isEmpty == false
        else { return .empty }

        let cacheKey = "\(artist.lowercased())|\(title.lowercased())"
        if let cached = cache.withLock({ $0[cacheKey] }) {
            switch cached {
            case let .match(match): return match
            case .noMatch: return .empty
            }
        }

        guard let searchURL = buildSearchURL(artist: artist, title: title) else { return .empty }

        guard let (data, response) = try? await session.data(from: searchURL),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return .empty }

        switch parseMatch(from: data) {
        case let .match(match):
            store(.match(match), forKey: cacheKey)
            return match
        case .noMatch:
            store(.noMatch, forKey: cacheKey)
            return .empty
        case .malformed:
            return .empty
        }
    }

    // MARK: - Private helpers

    private nonisolated struct SearchResponse: Decodable {
        let results: [SearchResult]
    }

    private nonisolated struct SearchResult: Decodable {
        let artworkUrl100: String?
        /// Direct Apple Music / iTunes Store page for the matched song.
        let trackViewUrl: String?
    }

    private static func buildSearchURL(artist: String, title: String) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        var queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(title)"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1")
        ]
        // Search the user's storefront — the API defaults to the US catalog,
        // which misses regional releases and returns wrong-region art.
        if let region = Locale.current.region?.identifier {
            queryItems.append(URLQueryItem(name: "country", value: region))
        }
        components?.queryItems = queryItems
        // `URLComponents` leaves `+` unescaped in query values, and the iTunes
        // API form-decodes it as a space — "Florence + The Machine" would lose
        // its `+` server-side. Escape it explicitly.
        if let escapedQuery = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B") {
            components?.percentEncodedQuery = escapedQuery
        }
        return components?.url
    }

    private static func store(_ value: CachedLookup, forKey key: String) {
        cache.withLock {
            if $0.count >= maxCacheEntries { $0.removeAll(keepingCapacity: true) }
            $0[key] = value
        }
    }

    private enum ParseOutcome {
        case match(Match)
        /// The catalog answered with no usable entry for this track — cacheable.
        case noMatch
        /// Undecodable payload — treat like a transport failure, don't cache.
        case malformed
    }

    /// Parses the first result into a ``Match``: the `artworkUrl100` field
    /// up-sized to 600 × 600 for crisp rendering on high-density displays, plus
    /// the `trackViewUrl` Apple Music link. A result with neither field is a
    /// (cacheable) miss.
    private static func parseMatch(from data: Data) -> ParseOutcome {
        guard let response = try? JSONDecoder().decode(SearchResponse.self, from: data) else {
            return .malformed
        }

        guard let result = response.results.first else { return .noMatch }

        // Apple returns 100×100; replace with 600×600 for album-art quality.
        let artworkURL = result.artworkUrl100
            .flatMap { URL(string: $0.replacingOccurrences(of: "100x100bb", with: "600x600bb")) }
        let appleMusicURL = validatedStoreURL(result.trackViewUrl)

        guard artworkURL != nil || appleMusicURL != nil else { return .noMatch }
        return .match(Match(artworkURL: artworkURL, appleMusicURL: appleMusicURL))
    }

    /// The `trackViewUrl` is untrusted network input that ends up at `openURL`,
    /// so accept it only if it is an HTTPS link to Apple's own storefront —
    /// never a `javascript:`, `file:`, or arbitrary-host URL. A non-conforming
    /// value is dropped (treated as "no link") rather than opened.
    private static func validatedStoreURL(_ string: String?) -> URL? {
        guard let string, let url = URL(string: string),
              url.scheme?.lowercased() == "https",
              let host = url.host()?.lowercased(),
              host == "music.apple.com" || host == "itunes.apple.com"
        else { return nil }
        return url
    }
}
