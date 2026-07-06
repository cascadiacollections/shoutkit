import Foundation
import Observation

/// A sleep timer that fires once after a chosen duration. Playback-agnostic:
/// the app layer wires ``onFire`` to `PlaybackController.pause()` at bootstrap,
/// keeping this type free of playback coupling (same hook pattern as
/// `onStationPlayed`).
///
/// While audio is playing the app stays alive in the background (`audio`
/// background mode), so the scheduled task fires reliably mid-stream — which is
/// the only case that matters for a sleep timer.
@MainActor
@Observable
public final class SleepTimer {
    /// When the timer will fire, or `nil` when inactive. Views derive the live
    /// countdown from this (e.g. via `TimelineView`) rather than the model
    /// ticking once a second.
    public private(set) var fireDate: Date?

    /// Invoked on the main actor when the timer elapses.
    @ObservationIgnored public var onFire: (() -> Void)?

    @ObservationIgnored private var timerTask: Task<Void, Never>?
    /// Injected clock so remaining-time math is testable.
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public var isActive: Bool { fireDate != nil }

    /// Starts (or restarts) the timer. A running timer is replaced.
    public func start(duration: TimeInterval) {
        timerTask?.cancel()

        let fireDate = now().addingTimeInterval(duration)
        self.fireDate = fireDate

        timerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, Task.isCancelled == false else { return }
            // A restart replaced this schedule while it slept.
            guard self.fireDate == fireDate else { return }

            self.fireDate = nil
            self.onFire?()
        }
    }

    public func cancel() {
        timerTask?.cancel()
        timerTask = nil
        fireDate = nil
    }

    /// Seconds until the timer fires as of `date`, or `nil` when inactive.
    public func remaining(asOf date: Date) -> TimeInterval? {
        guard let fireDate else { return nil }
        return max(0, fireDate.timeIntervalSince(date))
    }
}
