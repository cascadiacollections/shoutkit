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
        ///
        /// `current` is `nil` whenever there is nothing worth holding: the station
        /// has no artwork of its own (2026-08-16), or this is a cold start or a
        /// station switch (2026-09-02). In every one of those shapes the interim
        /// state is "nothing" rather than the still-unfetched `pending`, because a
        /// head unit asks for cover art once per identity and does not retry —
        /// advertising a URL backed only by a lazy network fetch spends that one
        /// request on an image that isn't ready.
        case hold(current: URL?, pending: URL)
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

        let target: URL?
        switch artwork {
        case .resolving:
            // Keep what's on screen. With nothing held — a cold start, or a
            // station switch — the station's own artwork is what we aim at next.
            target = held ?? stationArtworkURL
        case let .resolved(url):
            target = url ?? stationArtworkURL
        }

        guard let target else { return .present(nil) }
        // Already advertised, or servable without a fetch (bytes resident, or a
        // fetch already tried and failed — holding a stale image hostage to a URL
        // we cannot fetch is worse than showing the fallback).
        guard held != target, readyArtworkURLs.contains(target) == false else {
            return .present(target)
        }
        // Everything else waits for bytes, including the station switch that used
        // to be carved out of this check (2026-08-16). A switch is where the car
        // is *most* likely to be holding the previous app's cover, and presenting
        // an unfetched URL there spends its single request on nothing. The switch
        // is also rare and user-initiated, so the extra identity change it costs
        // doesn't touch the one-change-per-track budget this policy exists to keep.
        return .hold(current: held, pending: target)
    }
}

/// Whether a now-playing artwork fetch that has already failed should be tried
/// again yet.
///
/// Split out pure, like ``NowPlayingArtworkPolicy``, because the class that uses
/// it (`MediaSessionNowPlayingCenter`) is behind `canImport(NowPlaying)` and so
/// cannot be exercised by the host test suite at all. The decision worth pinning
/// down is this one, not the bookkeeping around it.
enum NowPlayingArtworkRetryPolicy {
    /// A failure is a delay, not a verdict. The case this exists for is a tunnel
    /// or a dead cell early in a drive: before, the first failed fetch marked a
    /// URL unavailable for the rest of the session — `clear()`, a full stop, was
    /// the only thing that reset it — so a station whose artwork missed once
    /// showed nothing for the whole drive.
    static let maximumAttempts = 5

    /// 5s, 15s, 45s, then 120s. Wide enough to still be retrying after a
    /// several-minute dead zone, and with `maximumAttempts` it bounds a genuinely
    /// dead URL (a 404 on a delisted station favicon) to five fetches per
    /// session rather than one per track boundary forever.
    static func retryDelay(afterAttempts attempts: Int) -> Duration {
        let schedule = [5, 15, 45, 120]
        let index = min(max(attempts, 1), schedule.count) - 1
        return .seconds(schedule[index])
    }

    /// - Parameters:
    ///   - attempts: how many times this URL's fetch has already failed. Zero
    ///               (never attempted) is always a go.
    ///   - elapsed:  time since the last failed attempt.
    static func shouldAttempt(afterAttempts attempts: Int, elapsed: Duration) -> Bool {
        guard attempts > 0 else { return true }
        guard attempts < maximumAttempts else { return false }
        return elapsed >= retryDelay(afterAttempts: attempts)
    }
}
