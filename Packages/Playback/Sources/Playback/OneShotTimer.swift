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
        let sleep = sleeper(on: clock, for: timeout)
        task = Task {
            try? await sleep()
            guard Task.isCancelled == false else { return }
            fire()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

/// A sleep whose deadline is `duration` from now — from when this is called,
/// not from when the returned closure first runs.
///
/// A timer task can start some time after it is scheduled. With the deadline
/// taken inside the task, that start-up delay was added to every timeout, and a
/// test that advanced a `TestClock` straight after scheduling could move time
/// before the deadline existed, so the timer never fired. Taking the deadline
/// on the caller makes the timeout mean the same thing wherever the task runs.
func sleeper(
    on clock: any Clock<Duration>,
    for duration: Duration,
) -> @Sendable () async throws -> Void {
    func deadlineSleep(on clock: some Clock<Duration>) -> @Sendable () async throws -> Void {
        let deadline = clock.now.advanced(by: duration)
        return { try await clock.sleep(until: deadline, tolerance: nil) }
    }
    return deadlineSleep(on: clock)
}
