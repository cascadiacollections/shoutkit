import Foundation
import RadioDirectory

/// Typed failure reason behind `PlaybackState.failed` / `AudioStatus.failed`,
/// mirroring `RadioDirectoryError`'s shape so a playback failure carries the
/// same localized-description/retryable contract a directory failure already
/// does, instead of an un-inspectable raw `String`.
public enum PlaybackError: Error, Equatable, LocalizedError, Sendable {
    /// No internet connection was available when the stream was attempted.
    case noInternet
    /// The station's stream endpoint was not accessible (e.g. 404 / resource gone).
    case stationNotAvailable(errorCode: Int)
    /// The stream itself failed after starting (`AVPlayerItem.status == .failed`).
    case streamFailed(String)
    /// Resolving the station's stream endpoint failed for a reason the
    /// directory layer already typed.
    case directory(RadioDirectoryError)

    public var errorDescription: String? {
        switch self {
        case .noInternet:
            String(localized: "No internet connection. Check your network and try again.", bundle: .module)
        case .stationNotAvailable:
            String(localized: "This station isn't available right now. Try again later.", bundle: .module)
        case let .streamFailed(message):
            message
        case let .directory(error):
            error.errorDescription
        }
    }

    /// Friendly, full-length message suitable for the Now Playing screen.
    /// Each case returns a pre-mapped string; the UI layer never interprets
    /// raw error codes.
    public var userMessage: String {
        switch self {
        case .noInternet:
            String(localized: "No internet connection. Check your network and try again.", bundle: .module)
        case .stationNotAvailable:
            String(localized: "This station isn't available right now. Try again later.", bundle: .module)
        case .streamFailed:
            String(localized: "The stream stopped unexpectedly. Tap to retry.", bundle: .module)
        case let .directory(error):
            error.userMessage
        }
    }

    /// Short message suitable for compact surfaces such as the mini player
    /// or lock screen.
    public var shortUserMessage: String {
        switch self {
        case .noInternet:
            String(localized: "No connection", bundle: .module)
        case .stationNotAvailable:
            String(localized: "Unavailable", bundle: .module)
        case .streamFailed:
            String(localized: "Stream error", bundle: .module)
        case let .directory(error):
            error.shortUserMessage
        }
    }

    /// Maps an arbitrary underlying error — typically one an audio engine raised
    /// — onto a typed case, using the same URL-error classification the
    /// `AVPlayer` path applies.
    ///
    /// Public because the concrete engine now lives in its own package
    /// (`PlaybackEngineAudioStreaming`, see #122) while the classification table
    /// belongs here, beside the cases it produces. `PlaybackFailure` itself stays
    /// internal: it is a lookup table, not API, and exporting it would put a
    /// second public error type in front of adopters for no gain.
    public static func classifying(_ error: any Error) -> PlaybackError {
        switch PlaybackFailure.classify(playerError: error, itemError: nil) {
        case .noInternet:
            return .noInternet
        case let .stationNotAvailable(errorCode: code):
            return .stationNotAvailable(errorCode: code)
        case let .playback(message):
            return .streamFailed(message)
        }
    }

    /// Whether the bounded auto-reconnect should retry this failure. Mirrors
    /// `RadioDirectoryError.isRetryable` for `.directory`; a mid-play stream
    /// failure or a lost internet connection is treated as transient.
    public var isRetryable: Bool {
        switch self {
        case .noInternet, .streamFailed:
            true
        case .stationNotAvailable:
            false
        case let .directory(error):
            error.isRetryable
        }
    }
}
