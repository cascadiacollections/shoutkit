import Playback
import RadioDirectory

/// A controller with a station already chosen, for the player previews.
///
/// The station is the longest-named of the preview set so the narrow-screen
/// previews exercise truncation. In a preview the engine is the stub, so the
/// controller settles into a connecting or failed state rather than playing —
/// which is fine for layout, and is itself a long second line worth seeing.
func previewPlaybackWithStation() -> PlaybackController {
    let playback = PlaybackController.preview()
    let stations = PreviewRadioDirectory.sampleStations
    if let station = stations.max(by: { $0.name.count < $1.name.count }) {
        playback.play(station)
    }
    return playback
}
