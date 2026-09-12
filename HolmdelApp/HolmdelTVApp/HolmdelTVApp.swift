import Persistence
import Playback
import RadioDirectory
import SwiftUI

@main
struct HolmdelTVApp: App {
    private let services: TVAppServices

    init() {
        services = TVAppDependencies.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            TVRootView()
                .modelContainer(services.container)
                .libraryStore(services.libraryStore)
                .playbackController(services.playbackController)
                .environment(\.tvDirectory, services.directory)
        }
    }
}

extension EnvironmentValues {
    // The station directory, injected the same way `Playback` and `Persistence`
    // inject theirs. Local to this target: the phone app reaches its directory
    // through the `Features/*` view models, which the tvOS MVP does not link.
    @Entry var tvDirectory: (any RadioDirectoryProviding)?
}
