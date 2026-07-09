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

    /// In-process positive-result cache. Negative results are NOT cached so a
    /// transient network failure on one track doesn't permanently suppress art
    /// for that track. Keyed on "artist|title" (lowercased). Values are tiny
    /// (a URL apiece), so unbounded growth over a listening session is fine.
    private static let cache = OSAllocatedUnfairLock<[String: URL]>(initialState: [:])

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
            return cached
        }

        guard let searchURL = buildSearchURL(artist: artist, title: title) else { return nil }

        guard let (data, response) = try? await session.data(from: searchURL),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }

        guard let artworkURL = parseArtworkURL(from: data) else { return nil }

        cache.withLock { $0[cacheKey] = artworkURL }
        return artworkURL
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
        return components?.url
    }

    /// Parses the first result's `artworkUrl100` field and up-sizes it to
    /// 600 × 600 for crisp rendering on high-density displays.
    private static func parseArtworkURL(from data: Data) -> URL? {
        guard let response = try? JSONDecoder().decode(SearchResponse.self, from: data),
              let urlString = response.results.first?.artworkUrl100
        else { return nil }

        // Apple returns 100×100; replace with 600×600 for album-art quality.
        let highRes = urlString.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        return URL(string: highRes)
    }
}
