import Testing

/// Parent of every suite in this target whose tests run inside
/// `withMainSerialExecutor`: the timer suites that drive a `TestClock`, and the
/// controller suites that wait for queued work with `drainMainQueue()`.
///
/// Inside it, the main actor's jobs and the global executor's share one FIFO
/// queue. A fixed number of yields (`drainMainQueue()`, or the ones inside
/// `TestClock.advance`) then runs everything already queued, and whatever
/// that work queues in turn, in the same order every time: a timer's task, its
/// sleep reaching the clock, the fire, an endpoint resolving off the main actor.
///
/// `withMainSerialExecutor` sets a process-wide runtime hook and restores the
/// previous value when it returns. Two calls that overlap can restore each
/// other's state: one test loses serial execution partway through, or the hook
/// stays on after both finish. `.serialized` here covers every suite nested
/// under it, so only one of these tests runs at a time; separate `.serialized`
/// suites would still run alongside each other, which is why there is one
/// parent. No suite outside it in this target uses the hook.
///
/// The other suites keep running in parallel. While a test here holds the
/// hook, their global-executor jobs run on the main queue too. That is slower
/// but not different: none of them block the main thread waiting on another
/// task. See DECISIONS.md, 2026-11-28.
@Suite(.serialized)
struct MainSerialExecutorTests {}
