import Foundation

/// What the controller knows about the current track's artwork at the moment it
/// pushes a now-playing update.
///
/// The distinction exists for surfaces where an artwork change is expensive.
/// The lock screen can flip images for free, so it never needed one; a Bluetooth
/// head unit does not. Over AVRCP an artwork change is a track-changed
/// notification followed by a cover-art transfer on a separate, slow channel, and
/// a car that is still fetching image *n* when *n+1* arrives commonly keeps
/// whatever it last managed to fetch — which, right after launch, is the previous
/// app's artwork. Telling the surface "a lookup is running" lets it hold what it
/// has instead of bouncing through the station favicon on the way to album art.
public enum NowPlayingArtwork: Sendable, Equatable {
    /// Resolution finished. `url` is the track's artwork, or `nil` when the track
    /// has none and the station's own artwork should stand in.
    case resolved(URL?)

    /// A lookup is in flight for the track being pushed. There is no answer yet,
    /// and there will be one shortly — the surface should keep advertising the
    /// artwork it is already showing for this station.
    case resolving
}

/// Which artwork a now-playing surface should advertise for an update, given what
/// it is already showing and what it can serve without going to the network.
///
/// Pure and framework-free on purpose: the host test suite covers it without the
/// iOS 27 NowPlaying framework (or MediaPlayer) being available.
enum NowPlayingArtworkPolicy {
    enum Decision: Equatable {
        /// Advertise `url` now.
        case present(URL?)

        /// Keep advertising `current` and fetch `pending` in the background. The
        /// surface re-runs the decision once `pending` is ready, and the identity
        /// flips exactly once — with the image already in hand.
        case hold(current: URL, pending: URL)
    }

    /// - Parameters:
    ///   - artwork:            what the controller knows about this track's artwork.
    ///   - stationArtworkURL:  the station's own artwork, used whenever there is no
    ///                         track artwork to show.
    ///   - presented:          the artwork URL the surface currently advertises.
    ///   - isSameStation:      whether `presented` belongs to the station being pushed.
    ///                         A station switch has nothing worth holding on to.
    ///   - readyArtworkURLs:   URLs the surface can advertise without a fetch first —
    ///                         bytes already resident, or a fetch already attempted
    ///                         and failed (holding a stale image hostage to a URL we
    ///                         cannot fetch is worse than showing the fallback).
    static func decide(
        artwork: NowPlayingArtwork,
        stationArtworkURL: URL?,
        presented: URL?,
        isSameStation: Bool,
        readyArtworkURLs: Set<URL>
    ) -> Decision {
        let held = isSameStation ? presented : nil

        switch artwork {
        case .resolving:
            // Hold what's on screen. With nothing held — first play, or a station
            // switch — the station's own artwork beats going blank.
            return .present(held ?? stationArtworkURL)

        case let .resolved(url):
            guard let target = url ?? stationArtworkURL else { return .present(nil) }
            guard let held, held != target, readyArtworkURLs.contains(target) == false else {
                return .present(target)
            }
            return .hold(current: held, pending: target)
        }
    }
}
