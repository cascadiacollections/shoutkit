import Foundation

/// Which artwork a player surface should show, and what it falls back to if that
/// image can't be loaded.
///
/// Shared by the mini player and the Now Playing screen so the two can never
/// disagree about what's on screen — they were drifting apart before this was
/// one function.
public struct EffectiveArtworkSelection: Equatable, Sendable {
    public let primaryURL: URL?
    public let fallbackURL: URL?

    public init(primaryURL: URL?, fallbackURL: URL?) {
        self.primaryURL = primaryURL
        self.fallbackURL = fallbackURL
    }
}

public enum EffectiveArtwork {
    /// Picks the artwork to show: resolved album art when the listener has left
    /// catalog lookups on, the station's own artwork otherwise.
    ///
    /// Takes plain values rather than `SettingsStore`/`PlaybackController`/`Station`
    /// so the rule can be exercised without a SwiftData container or a live
    /// playback graph; `PlayerFeature` owns the thin adapter that reads those
    /// types and calls this.
    public static func selection(
        isAlbumArtEnabled: Bool,
        albumArtURL: URL?,
        stationArtworkURL: URL?
    ) -> EffectiveArtworkSelection {
        guard isAlbumArtEnabled, let albumArtURL else {
            // No fallback in this branch, deliberately: the station's artwork is
            // already the primary, and naming it as its own fallback would make a
            // failed load look retryable to the artwork loader when it isn't.
            return EffectiveArtworkSelection(primaryURL: stationArtworkURL, fallbackURL: nil)
        }
        // Album art can 404 or resolve to a track the station never played;
        // the station's own artwork is what the surface drops back to.
        return EffectiveArtworkSelection(primaryURL: albumArtURL, fallbackURL: stationArtworkURL)
    }
}
