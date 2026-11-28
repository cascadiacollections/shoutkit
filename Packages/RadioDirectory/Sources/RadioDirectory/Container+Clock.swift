import FactoryKit
import Foundation

public extension Container {
    /// Monotonic clock for the discovery cache TTL and for playback's
    /// reconnect, stall, and sleep timers. Production is ``ContinuousClock``.
    /// A test that needs to move time passes a `TestClock` into the initializer
    /// instead of replacing this, so one suite cannot leak a clock into the next.
    var clock: Factory<any Clock<Duration>> {
        self { ContinuousClock() }
            .scope(.singleton)
    }
}

/// The clock `AppDependencies` and the watch and TV apps pass into production
/// types. Resolves ``Container/clock`` and keeps `ContinuousClock` when a test
/// double was registered: those types that store a concrete clock cannot hold
/// an arbitrary one, and tests pass their `TestClock` in directly.
public func productionClock() -> ContinuousClock {
    if let clock = Container.shared.clock() as? ContinuousClock {
        return clock
    }
    return ContinuousClock()
}
