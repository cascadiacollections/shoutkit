import Foundation

/// Shared in-app artwork policy: clear on identity change, retry transient
/// failures, and fall back to station art when album art cannot be loaded.
public struct ArtworkLoadRequest: Equatable, Sendable {
    public let primaryURL: URL?
    public let fallbackURL: URL?

    public init(primaryURL: URL?, fallbackURL: URL? = nil) {
        self.primaryURL = primaryURL
        self.fallbackURL = fallbackURL
    }

    var candidateURLs: [URL] {
        var urls: [URL] = []
        if let primaryURL {
            urls.append(primaryURL)
        }
        if let fallbackURL, fallbackURL != primaryURL {
            urls.append(fallbackURL)
        }
        return urls
    }
}

public enum ArtworkLoadPolicy {
    public static let defaultRetryDelays: [Duration] = [
        .milliseconds(350),
        .seconds(1)
    ]

    public static func load<Artwork>(
        _ request: ArtworkLoadRequest,
        retryDelays: [Duration] = defaultRetryDelays,
        loader: @escaping (URL?) async -> Artwork?
    ) async -> Artwork? {
        await loadWithSource(
            request,
            retryDelays: retryDelays,
            loader: loader
        )?.artwork
    }

    public static func loadWithSource<Artwork>(
        _ request: ArtworkLoadRequest,
        retryDelays: [Duration] = defaultRetryDelays,
        loader: @escaping (URL?) async -> Artwork?
    ) async -> (artwork: Artwork, sourceURL: URL)? {
        for url in request.candidateURLs {
            var attempt = 0
            while true {
                guard Task.isCancelled == false else { return nil }
                if let artwork = await loader(url) {
                    return (artwork, url)
                }
                guard attempt < retryDelays.count else { break }
                let delay = retryDelays[attempt]
                attempt += 1
                try? await Task.sleep(for: delay)
            }
        }
        return nil
    }
}
