import Foundation

/// A cancellable, restartable one-shot timer on the main actor — the
/// `SleepTimer` task pattern without the observable surface. Backs the
/// paused-release, stall-ceiling, reconnect, and interruption windows in
/// `PlaybackController`. The clock is injectable so a test can advance a
/// `TestClock` instead of waiting out the real delay.
@MainActor
final class OneShotTimer {
    private let clock: any Clock<Duration>
    private var task: Task<Void, Never>?

    init(clock: any Clock<Duration>) {
        self.clock = clock
    }

    /// Schedules `fire` after `timeout`, replacing any pending schedule.
    func schedule(after timeout: Duration, fire: @escaping @MainActor () -> Void) {
        task?.cancel()
        let clock = self.clock
        task = Task {
            try? await clock.sleep(for: timeout)
            guard Task.isCancelled == false else { return }
            fire()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
