import Persistence
import Playback
import SwiftUI

@main
struct HolmdelWatchApp: App {
    private let services: WatchAppServices

    init() {
        services = WatchAppDependencies.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchRootView()
            }
            .modelContainer(services.container)
            .libraryStore(services.libraryStore)
            .playbackController(services.playbackController)
            .onOpenURL { url in
                if WatchLaunchRoute.isPlayLast(url) {
                    WatchAppDependencies.playLastStation()
                }
            }
        }
    }
}
