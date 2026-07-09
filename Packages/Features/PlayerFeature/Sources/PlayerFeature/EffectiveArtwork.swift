import Foundation
import Persistence
import Playback
import RadioDirectory

/// The artwork URL to display: album art when the feature is enabled and a
/// URL has been resolved, otherwise the station's own artwork. Shared by the
/// mini player and Now Playing so the two surfaces can never disagree.
func effectiveArtworkURL(
    settings: SettingsStore?,
    playback: PlaybackController?,
    station: Station?
) -> URL? {
    if settings?.isAlbumArtEnabled == true, let albumArt = playback?.albumArtURL {
        return albumArt
    }
    return station?.artworkURL
}
