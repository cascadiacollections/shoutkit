import AppIntents
import DesignSystem
import Persistence
import Playback
import RadioDirectory
import SwiftData
import SwiftUI

@main
struct ShoutKitApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let backgroundRefresh = BackgroundRefreshController()
    private let services: AppServices

    init() {
        services = AppDependencies.bootstrap()
        backgroundRefresh.register()
        // Kick App Shortcuts registration immediately; bootstrap() follows with
        // a second refresh after Spotlight indexing completes so Shortcuts
        // search and Siri both see the same station set.
        ShoutKitShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                launchRouter: services.stationLaunchRouter,
                isPersistentStoreAvailable: services.isPersistentStoreAvailable
            )
                .modelContainer(services.container)
                .libraryStore(services.libraryStore)
                .playbackController(services.playbackController)
                .sleepTimer(services.sleepTimer)
                .settingsStore(services.settingsStore)
                .tint(.shoutKitAccent)
                .onChange(of: services.settingsStore.isDiagnosticsSharingEnabled) { _, _ in
                    services.diagnosticsService.refreshSubscription()
                }
                .onOpenURL { url in
                    services.stationLaunchRouter.open(url: url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        backgroundRefresh.schedule()
                    }
                }
        }
    }
}
