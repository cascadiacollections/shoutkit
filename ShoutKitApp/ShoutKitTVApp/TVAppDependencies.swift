import Foundation
import Persistence
import Playback
import RadioDirectory
import SwiftData

@MainActor
struct TVAppServices {
    let container: ModelContainer
    let libraryStore: LibraryStore
    let playbackController: PlaybackController
    /// Exposed (the watch app does not) because the TV browses: `TVRootView` loads
    /// `topStations(limit:)` for its shelf, and there is no `Features/*` view model
    /// on this platform to hold a directory of its own.
    let directory: any RadioDirectoryProviding
}

/// Service graph for the tvOS app, modelled on `WatchAppDependencies`.
///
/// Like the watch, this calls `PlaybackController`'s **designated** initializer with
/// every collaborator explicit and **bypasses Factory entirely** — and so does *not*
/// call `registerProductionPlaybackEngine()`. That is deliberate: the Factory-resolved
/// path exists for the iOS app, and inheriting it here would resolve
/// `StubRadioPlaybackEngine` and play silence (see DECISIONS.md on the `os(iOS)` gates).
///
/// The WatchConnectivity last-station sync has no tvOS counterpart and is dropped: a TV
/// is not a companion device, so recents come from this device's own store.
@MainActor
enum TVAppDependencies {
    private static var services: TVAppServices?

    @discardableResult
    static func bootstrap() -> TVAppServices {
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
            output: TVRadioPlaybackEngine(),
            nowPlayingCenter: TVNowPlayingCenter()
        )
        playbackController.onStationPlayed = { station in
            libraryStore.logRecent(station)
        }

        let services = TVAppServices(
            container: container,
            libraryStore: libraryStore,
            playbackController: playbackController,
            directory: directory
        )
        Self.services = services
        return services
    }
}
