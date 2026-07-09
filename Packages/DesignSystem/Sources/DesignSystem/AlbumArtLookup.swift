import Foundation

/// Best-effort album artwork discovery via the public iTunes Search API.
///
/// Queries are session-cached so repeated lookups for the same artist/title
/// don't leave the app's sandbox. The service is deliberately simple —
/// one hit per track, nil on any failure — to stay true to the "best effort"
/// contract callers expect.
public enum AlbumArtLookup {
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
    /// for that track. Keyed on "artist|title" (lowercased).
    private static let cache = NSCache<NSString, NSURL>()

    /// Resolves a high-quality artwork URL for the given artist and title.
    ///
    /// - Parameters:
    ///   - artist: The performing artist.
    ///   - title:  The track title.
    /// - Returns: An artwork URL at up to 600 × 600 points, or `nil` when
    ///   either parameter is absent/empty or when the lookup fails.
    public nonisolated static func artworkURL(artist: String?, title: String?) async -> URL? {
        guard let artist, let title,
              artist.isEmpty == false, title.isEmpty == false
        else { return nil }

        let cacheKey = "\(artist.lowercased())|\(title.lowercased())" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached as URL
        }

        guard let searchURL = buildSearchURL(artist: artist, title: title) else { return nil }

        guard let (data, response) = try? await session.data(from: searchURL),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }

        guard let artworkURL = parseArtworkURL(from: data) else { return nil }

        cache.setObject(artworkURL as NSURL, forKey: cacheKey)
        return artworkURL
    }

    // MARK: - Private helpers

    private static func buildSearchURL(artist: String, title: String) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(title)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        return components?.url
    }

    /// Parses the first result's `artworkUrl100` field and up-sizes it to
    /// 600 × 600 for crisp rendering on high-density displays.
    private static func parseArtworkURL(from data: Data) -> URL? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first,
              let urlString = first["artworkUrl100"] as? String
        else { return nil }

        // Apple returns 100×100; replace with 600×600 for album-art quality.
        let highRes = urlString.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        return URL(string: highRes)
    }
}
