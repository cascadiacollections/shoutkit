import Testing

/// Parent of the suites that drive playback timers with a `TestClock`.
///
/// Those tests run inside `withMainSerialExecutor`, so the timer's task, its
/// sleep reaching the clock, and the fire all go through one FIFO queue, and
/// the yields inside `TestClock.advance` let each of them run before time
/// moves and before `advance` returns. Without it, a sleep could register
/// after the clock had already moved.
///
/// `withMainSerialExecutor` sets a process-wide runtime hook and restores the
/// previous value when it returns, so two overlapping calls can undo each
/// other. `.serialized` here covers every suite nested under it, and no suite
/// outside it in this target uses the hook. The other suites still run in
/// parallel; while a test here holds the hook their global-executor jobs run
/// on the main queue too, which is slower but not different, since none of
/// them block the main thread waiting on another task.
@Suite(.serialized)
struct PlaybackTimingTests {}
