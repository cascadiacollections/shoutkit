import Foundation

/// A cancellable, restartable one-shot timer on the main actor — the
/// `SleepTimer` task pattern without the observable surface. Backs the
/// paused-release and stall-ceiling windows in `PlaybackController`.
@MainActor
final class OneShotTimer {
    private var task: Task<Void, Never>?

    /// Schedules `fire` after `timeout`, replacing any pending schedule.
    func schedule(after timeout: Duration, fire: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: timeout)
            guard Task.isCancelled == false else { return }
            fire()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
