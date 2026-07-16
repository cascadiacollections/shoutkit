import Foundation
import Persistence
import Playback
import RadioDirectory
import SwiftData

@MainActor
struct WatchAppServices {
    let container: ModelContainer
    let libraryStore: LibraryStore
    let playbackController: PlaybackController
}

@MainActor
enum WatchAppDependencies {
    private static var services: WatchAppServices?

    @discardableResult
    static func bootstrap() -> WatchAppServices {
        if let services {
            return services
        }

        let container = ShoutKitModelContainer.makeContainer()
        let libraryStore = LibraryStore(context: container.mainContext)
        let directory = CachingRadioDirectory(
            base: PreferredRadioDirectory(base: RadioBrowserDirectoryClient())
        )
        let playbackController = PlaybackController(
            directory: directory,
            output: WatchRadioPlaybackEngine(),
            nowPlayingCenter: WatchNoopNowPlayingCenter()
        )
        playbackController.onStationPlayed = { station in
            libraryStore.logRecent(station)
        }

        let services = WatchAppServices(
            container: container,
            libraryStore: libraryStore,
            playbackController: playbackController
        )
        Self.services = services
        return services
    }

    static func playLastStation() {
        let services = bootstrap()
        guard let station = services.libraryStore.mostRecentStation() else { return }

        switch services.playbackController.phase(for: station) {
        case .playing, .loading:
            break
        case .paused, .failed:
            services.playbackController.resume()
        case .idle:
            services.playbackController.play(station)
        }
    }
}
