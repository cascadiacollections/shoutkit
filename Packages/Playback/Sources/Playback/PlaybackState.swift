import Foundation
import RadioDirectory

/// High-level playback state the UI binds to. `buffering` is distinguished from
/// `playing` so surfaces can show a spinner while a stream connects.
public enum PlaybackState: Equatable, Sendable {
    case idle
    case loading(Station)
    case buffering(Station)
    case playing(Station)
    case paused(Station)
    case failed(String)

    /// The station associated with the current state, if any.
    public var station: Station? {
        switch self {
        case .idle, .failed:
            return nil
        case let .loading(station),
             let .buffering(station),
             let .playing(station),
             let .paused(station):
            return station
        }
    }

    public var isActive: Bool {
        switch self {
        case .idle, .failed:
            return false
        default:
            return true
        }
    }
}

/// Per-station phase used by list rows to render the correct play/pause affordance.
public enum StationPlaybackPhase: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case failed(String)
}
