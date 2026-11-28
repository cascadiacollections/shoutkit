import Foundation

/// ``CachingRadioDirectory`` parameterized on ``ContinuousClock``, which is
/// what every production call site and every test that does not move time
/// constructs. The clock comes from ``productionClock()`` so Factory stays the
/// composition root. Tests that pass a `TestClock` use the generic initializer.
extension CachingRadioDirectory where C == ContinuousClock {
    public init(
        base: any RadioDirectoryProviding,
        timeToLive: TimeInterval = 60,
        snapshotStore: (any DirectorySnapshotStoring)? = nil,
        snapshotTimeToLive: TimeInterval = CachingRadioDirectory<ContinuousClock>.defaultSnapshotTimeToLive,
        snapshotIdentity: @escaping @Sendable () async -> String? = { nil },
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.init(
            base: base,
            timeToLive: timeToLive,
            snapshotStore: snapshotStore,
            snapshotTimeToLive: snapshotTimeToLive,
            snapshotIdentity: snapshotIdentity,
            now: now,
            clock: productionClock(),
        )
    }
}
