#if canImport(UIKit)
import Foundation
import RadioDirectory

public extension PlaybackController {
    /// Production wiring: AVPlayer-backed audio and the system now-playing center.
    /// On iOS 27+ the now-playing surface is the NowPlaying framework's typed
    /// MediaSession; iOS 26 keeps the legacy MediaPlayer bridge. Both sit behind
    /// ``NowPlayingPresenting``, so nothing else changes with the OS version.
    convenience init(directory: any RadioDirectoryProviding) {
        let nowPlayingCenter: any NowPlayingPresenting
        #if canImport(NowPlaying)
        if #available(iOS 27, *) {
            nowPlayingCenter = MediaSessionNowPlayingCenter()
        } else {
            nowPlayingCenter = NowPlayingCenter()
        }
        #else
        nowPlayingCenter = NowPlayingCenter()
        #endif

        self.init(
            directory: directory,
            output: AVPlayerAudioOutput(),
            nowPlayingCenter: nowPlayingCenter
        )
    }

    /// A controller wired to preview data for SwiftUI previews.
    static func preview() -> PlaybackController {
        PlaybackController(directory: PreviewRadioDirectory())
    }
}
#endif
