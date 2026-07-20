import Foundation
import Persistence
import Playback
import RadioDirectory
import SwiftData
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

@MainActor
struct WatchAppServices {
    let container: ModelContainer
    let libraryStore: LibraryStore
    let playbackController: PlaybackController
}

@MainActor
enum WatchAppDependencies {
    private static var services: WatchAppServices?
    private static let watchLastStationSync = WatchLastStationSync()

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
        watchLastStationSync.activate()
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
        let localRecent = services.libraryStore.mostRecentStation()
        guard let station = localRecent ?? watchLastStationSync.syncedStation() else { return }
        if localRecent?.id != station.id {
            services.libraryStore.logRecent(station)
        }

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

#if canImport(WatchConnectivity)

private final class WatchLastStationSync: NSObject, WCSessionDelegate {
    private enum Keys {
        static let lastStation = "watchSync.lastStation"
    }

    private let session: WCSession?
    private let decoder = JSONDecoder()
    private let defaults: UserDefaults

    override init() {
        defaults = .standard
        if WCSession.isSupported() {
            let session = WCSession.default
            self.session = session
        } else {
            session = nil
        }
        super.init()
    }

    func activate() {
        session?.delegate = self
        session?.activate()
    }

    func syncedStation() -> Station? {
        guard let data = defaults.data(forKey: Keys.lastStation) else { return nil }
        return try? decoder.decode(Station.self, from: data)
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[Keys.lastStation] as? Data else { return }
        defaults.set(data, forKey: Keys.lastStation)
    }
}

#else

private final class WatchLastStationSync {
    func activate() {}
    func syncedStation() -> Station? { nil }
}

#endif
