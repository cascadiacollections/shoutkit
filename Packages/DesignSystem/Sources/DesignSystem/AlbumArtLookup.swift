import Foundation
import os

/// Best-effort album artwork discovery via the public iTunes Search API.
///
/// Queries are session-cached so repeated lookups for the same artist/title
/// don't leave the app's sandbox. The service is deliberately simple —
/// one hit per track, nil on any failure — to stay true to the "best effort"
/// contract callers expect.
///
/// `nonisolated` opts the whole type out of the package's main-actor default:
/// this is pure networking with `Sendable` shared state (session + locked
/// cache), and lookups must not tie up the main actor.
public nonisolated enum AlbumArtLookup {
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
        case artwork(URL)
        case noMatch
    }

    /// Values are tiny, but a multi-day session shouldn't grow unbounded:
    /// past the cap the cache is simply reset (a rare full re-warm is cheaper
    /// than LRU bookkeeping on every lookup).
    private static let maxCacheEntries = 256

    private static let cache = OSAllocatedUnfairLock<[String: CachedLookup]>(initialState: [:])

    /// Resolves a high-quality artwork URL for the given artist and title.
    ///
    /// - Parameters:
    ///   - artist: The performing artist.
    ///   - title:  The track title.
    /// - Returns: An artwork URL at up to 600 × 600 points, or `nil` when
    ///   either parameter is absent/empty or when the lookup fails.
    public static func artworkURL(artist: String?, title: String?) async -> URL? {
        guard let artist = artist?.trimmingCharacters(in: .whitespacesAndNewlines),
              let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              artist.isEmpty == false, title.isEmpty == false
        else { return nil }

        let cacheKey = "\(artist.lowercased())|\(title.lowercased())"
        if let cached = cache.withLock({ $0[cacheKey] }) {
            switch cached {
            case let .artwork(url): return url
            case .noMatch: return nil
            }
        }

        guard let searchURL = buildSearchURL(artist: artist, title: title) else { return nil }

        guard let (data, response) = try? await session.data(from: searchURL),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }

        switch parseArtworkURL(from: data) {
        case let .found(artworkURL):
            store(.artwork(artworkURL), forKey: cacheKey)
            return artworkURL
        case .noMatch:
            store(.noMatch, forKey: cacheKey)
            return nil
        case .malformed:
            return nil
        }
    }

    // MARK: - Private helpers

    private nonisolated struct SearchResponse: Decodable {
        let results: [SearchResult]
    }

    private nonisolated struct SearchResult: Decodable {
        let artworkUrl100: String?
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
        case found(URL)
        /// The catalog answered and has no artwork for this track — cacheable.
        case noMatch
        /// Undecodable payload — treat like a transport failure, don't cache.
        case malformed
    }

    /// Parses the first result's `artworkUrl100` field and up-sizes it to
    /// 600 × 600 for crisp rendering on high-density displays.
    private static func parseArtworkURL(from data: Data) -> ParseOutcome {
        guard let response = try? JSONDecoder().decode(SearchResponse.self, from: data) else {
            return .malformed
        }

        // Apple returns 100×100; replace with 600×600 for album-art quality.
        guard let urlString = response.results.first?.artworkUrl100,
              let url = URL(string: urlString.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
        else { return .noMatch }

        return .found(url)
    }
}
