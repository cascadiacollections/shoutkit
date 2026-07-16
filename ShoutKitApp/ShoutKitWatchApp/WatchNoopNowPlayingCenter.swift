import Foundation
import Playback
import RadioDirectory

@MainActor
final class WatchNoopNowPlayingCenter: NowPlayingPresenting {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onToggle: (() -> Void)?

    func update(station: Station, track: NowPlayingMetadata?, isPlaying: Bool, artworkURL: URL?) {}

    func clear() {}
}
