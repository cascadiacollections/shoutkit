import Persistence
import Playback
import RadioDirectory
import SwiftUI

@main
struct ShoutKitTVApp: App {
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

private struct TVDirectoryKey: EnvironmentKey {
    static let defaultValue: (any RadioDirectoryProviding)? = nil
}

extension EnvironmentValues {
    /// The station directory, injected the same way `Playback` and `Persistence`
    /// inject theirs. Local to this target: the phone app reaches its directory
    /// through the `Features/*` view models, which the tvOS MVP does not link.
    var tvDirectory: (any RadioDirectoryProviding)? {
        get { self[TVDirectoryKey.self] }
        set { self[TVDirectoryKey.self] = newValue }
    }
}
