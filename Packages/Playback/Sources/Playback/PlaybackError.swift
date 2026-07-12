import Foundation
import RadioDirectory

/// Typed failure reason behind `PlaybackState.failed` / `AudioStatus.failed`,
/// mirroring `RadioDirectoryError`'s shape so a playback failure carries the
/// same localized-description/retryable contract a directory failure already
/// does, instead of an un-inspectable raw `String`.
public enum PlaybackError: Error, Equatable, LocalizedError, Sendable {
    /// The stream itself failed after starting (`AVPlayerItem.status == .failed`).
    case streamFailed(String)
    /// Resolving the station's stream endpoint failed for a reason the
    /// directory layer already typed.
    case directory(RadioDirectoryError)

    public var errorDescription: String? {
        switch self {
        case let .streamFailed(message):
            message
        case let .directory(error):
            error.errorDescription
        }
    }

    /// Whether the bounded auto-reconnect should retry this failure. Mirrors
    /// `RadioDirectoryError.isRetryable` for `.directory`; a mid-play stream
    /// failure is always treated as transient, same as
    /// `RadioDirectoryError.transport`.
    public var isRetryable: Bool {
        switch self {
        case .streamFailed:
            true
        case let .directory(error):
            error.isRetryable
        }
    }
}
