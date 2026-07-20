import Foundation
import Persistence
import Playback
import RadioDirectory

/// The artwork URL to display: album art when the feature is enabled and a
/// URL has been resolved, otherwise the station's own artwork. Shared by the
/// mini player and Now Playing so the two surfaces can never disagree.
struct EffectiveArtworkSelection: Equatable {
    let primaryURL: URL?
    let fallbackURL: URL?
}

func effectiveArtworkSelection(
    settings: SettingsStore?,
    playback: PlaybackController?,
    station: Station?
) -> EffectiveArtworkSelection {
    if settings?.isAlbumArtEnabled == true, let albumArt = playback?.albumArtURL {
        return EffectiveArtworkSelection(primaryURL: albumArt, fallbackURL: station?.artworkURL)
    }
    return EffectiveArtworkSelection(primaryURL: station?.artworkURL, fallbackURL: nil)
}

func effectiveArtworkURL(
    settings: SettingsStore?,
    playback: PlaybackController?,
    station: Station?
) -> URL? {
    effectiveArtworkSelection(
        settings: settings,
        playback: playback,
        station: station
    ).primaryURL
}
