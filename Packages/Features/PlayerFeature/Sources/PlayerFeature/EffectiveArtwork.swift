import Foundation
import Persistence
import Playback
import PlayerFeatureCore
import RadioDirectory

/// Adapter from the app's concrete observable types to the pure selection rule
/// in `PlayerFeatureCore`.
///
/// The split exists so the rule can be tested: this package depends on
/// DesignSystem, whose UIKit-only sources don't build for the mac host at all,
/// so nothing here can be reached by `swift test`. Same shape as
/// BrowseFeature/BrowseFeatureCore.
///
/// Keep this a translation and nothing more — a decision that lands here is a
/// decision that can't be tested.
func effectiveArtworkSelection(
    settings: SettingsStore?,
    playback: PlaybackController?,
    station: Station?
) -> EffectiveArtworkSelection {
    EffectiveArtwork.selection(
        isAlbumArtEnabled: settings?.isAlbumArtEnabled == true,
        albumArtURL: playback?.albumArtURL,
        stationArtworkURL: station?.artworkURL
    )
}
