import AppIntents
import DesignSystem
import Persistence
import Playback
import RadioDirectory
import SwiftData
import SwiftUI

@main
struct ShoutKitApp: App {
    private let services: AppServices

    init() {
        services = AppDependencies.bootstrap()
        // Let Siri pre-register station names for the parameterized
        // "Play <station> on ShoutKit" phrase.
        ShoutKitShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView(directory: services.directory)
                .modelContainer(services.container)
                .libraryStore(services.libraryStore)
                .playbackController(services.playbackController)
                .sleepTimer(services.sleepTimer)
                .settingsStore(services.settingsStore)
                .tint(.shoutKitAccent)
        }
    }
}
