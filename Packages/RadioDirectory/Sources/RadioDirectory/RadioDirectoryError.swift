import Foundation

/// Every failure surfaced by ``RadioDirectoryProviding``.
///
/// All eight requirements of that protocol are declared
/// `throws(RadioDirectoryError)`, so this enum is the package's entire error
/// vocabulary — a conformance backed by some other directory service maps its
/// failures into these cases rather than defining its own type.
///
/// - Note: This enum is not frozen and gains cases as new failure modes are
///   found. Exhaustive `switch`es over it are a source-compatibility risk;
///   prefer ``userMessage``, ``shortUserMessage``, and ``isRetryable``, which
///   are total by construction.
public enum RadioDirectoryError: Error, Equatable, LocalizedError, Sendable {
    /// A station's PLS/M3U playlist parsed successfully but named no stream.
    case emptyPlaylist

    /// The directory answered with a non-success HTTP status.
    case httpStatus(Int)

    /// The response was well-formed HTTP but not something this client can read.
    case invalidResponse

    /// A request URL could not be assembled — usually a host or query value that
    /// will not percent-encode.
    case invalidURL

    /// The directory needs an API key and none was supplied. For SHOUTcast this
    /// means `SHOUTCAST_DEV_KEY` was unset at build time; Radio-Browser is
    /// keyless and never raises it. Not retryable — the fix is a build
    /// configuration change, not another request.
    case missingAPIKey

    /// The response body could not be decoded. The payload is a diagnostic
    /// message from the throw site, not a localized string.
    case parsingFailed(String)

    /// The request never completed: offline, DNS failure, timeout, TLS refusal.
    /// The payload is `URLError.localizedDescription` when the transport
    /// supplied one, `nil` otherwise.
    case transport(String?)

    public var errorDescription: String? {
        switch self {
        case .emptyPlaylist:
            String(localized: "The station did not return a playable stream.", bundle: .module)
        case let .httpStatus(statusCode):
            String(localized: "The station directory returned HTTP \(statusCode).", bundle: .module)
        case .invalidResponse:
            String(localized: "The station directory returned an invalid response.", bundle: .module)
        case .invalidURL:
            String(localized: "The station directory URL could not be built.", bundle: .module)
        case .missingAPIKey:
            // Reaches an end user through LocalizedError, so it says what they can
            // observe. The build-time cause (an unset SHOUTCAST_DEV_KEY) belongs in
            // the log and in the case's doc comment, not on someone's screen.
            String(localized: "Live stations are unavailable right now.", bundle: .module)
        case let .parsingFailed(message):
            // Constructed at the throw site — either a literal we authored
            // (already wrapped there) or a system-provided description.
            message
        case let .transport(message):
            // System-provided (URLSession's localizedDescription) when non-nil.
            message ?? String(
                localized: "The station directory could not be reached. Check your connection.",
                bundle: .module
            )
        }
    }

    /// Whether retrying the same request might plausibly succeed — lets the UI
    /// distinguish "try again" failures (network) from permanent ones (bad data).
    public var isRetryable: Bool {
        switch self {
        case .transport, .httpStatus, .invalidResponse, .emptyPlaylist:
            true
        case .invalidURL, .missingAPIKey, .parsingFailed:
            false
        }
    }

    /// Friendly, full-length message suitable for the Now Playing screen.
    /// Each case returns a pre-mapped string; the UI layer never interprets
    /// raw error codes.
    public var userMessage: String {
        switch self {
        case .transport:
            String(localized: "Can't reach the station. Check your connection.", bundle: .module)
        case .emptyPlaylist, .httpStatus, .invalidResponse:
            String(localized: "The station isn't available right now.", bundle: .module)
        case .invalidURL, .missingAPIKey, .parsingFailed:
            String(localized: "The station has a configuration problem.", bundle: .module)
        }
    }

    /// Short message suitable for compact surfaces such as the mini player
    /// or lock screen.
    public var shortUserMessage: String {
        switch self {
        case .transport:
            String(localized: "No connection", bundle: .module)
        case .emptyPlaylist, .httpStatus, .invalidResponse:
            String(localized: "Unavailable", bundle: .module)
        case .invalidURL, .missingAPIKey, .parsingFailed:
            String(localized: "Station error", bundle: .module)
        }
    }
}
