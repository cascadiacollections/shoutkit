import SwiftUI

public extension EnvironmentValues {
    /// The app-wide playback controller. `nil` until the app injects it at the root,
    /// so feature views should guard before driving playback.
    @Entry var playbackController: PlaybackController?

    /// The app-wide sleep timer. `nil` until injected at the root.
    @Entry var sleepTimer: SleepTimer?
}

public extension View {
    func playbackController(_ controller: PlaybackController) -> some View {
        environment(\.playbackController, controller)
    }

    func sleepTimer(_ timer: SleepTimer) -> some View {
        environment(\.sleepTimer, timer)
    }
}
