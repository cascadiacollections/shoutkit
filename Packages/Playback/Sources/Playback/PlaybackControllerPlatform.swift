#if canImport(UIKit)
import Foundation
import RadioDirectory

public extension PlaybackController {
    /// Production wiring: AVPlayer-backed audio and the system now-playing center.
    /// Keep the lock-screen / Control Center surface on the MediaPlayer bridge for
    /// now: on-device iOS 27 builds have shown Live Activity album art correctly
    /// while the system Now Playing surface can stick to station artwork. Both
    /// implementations sit behind ``NowPlayingPresenting``, so this is a safe
    /// runtime switch until the typed MediaSession path is fully parity-tested.
    convenience init(directory: any RadioDirectoryProviding) {
        self.init(
            directory: directory,
            output: AVPlayerAudioOutput(),
            nowPlayingCenter: NowPlayingCenter()
        )
    }

    /// A controller wired to preview data for SwiftUI previews.
    static func preview() -> PlaybackController {
        PlaybackController(directory: PreviewRadioDirectory())
    }
}
#endif
