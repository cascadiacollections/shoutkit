import AVFoundation
import os

/// The level meter as an ``AudioTapPlugin``: an ``AudioSpectrumAnalyzer`` plus
/// what a meter needs on top of raw levels — a cap on how often it publishes,
/// and ballistics (fast rise, slow fall) so bars read as motion, not flicker.
/// Published frames arrive on ``levels``.
///
/// ```swift
/// guard let meter = AudioLevelMeter() else { return }
/// taps.add(meter)
/// for await frame in meter.levels { draw(frame) }
/// ```
///
/// ``levels`` is handed out once, keeps only the newest unread frame, and the
/// meter holds no reference to it afterwards. So the stream ends — and
/// ``onTermination(_:)`` runs — whenever its consumer is cancelled *or* simply
/// stops iterating, which is the signal to detach the meter from its engine.
///
/// `@unchecked Sendable` because the state behind the lock holds the
/// non-`Sendable` analyzer, and each call hands it a non-`Sendable`
/// `AVAudioPCMBuffer`. A `Mutex` refuses that pairing (region isolation can't
/// prove the buffer stays out of the state), and it does: the analyzer copies
/// samples out and keeps no reference. Every access goes through the lock.
public final class AudioLevelMeter: AudioTapPlugin, @unchecked Sendable {
    /// Spec ballistics. How much of the gap to a louder reading closes per frame.
    public static let attack: Float = 0.7

    /// How much of the gap to a quieter reading closes per frame.
    public static let release: Float = 0.18

    /// The default publishing cap: 30 frames a second is as fast as bars need to
    /// move. Engines that tap in ~100 ms buffers (AudioStreaming on Apple
    /// platforms delivers 4410 frames at 44.1 kHz) never reach it.
    public static let defaultMinimumInterval = Duration.milliseconds(33)

    private struct State {
        let analyzer: AudioSpectrumAnalyzer
        var smoothed: [Float]
        var lastPublished: ContinuousClock.Instant?
    }

    public let minimumInterval: Duration

    /// Published frames. The first read takes the stream; later reads get one
    /// that is already finished.
    public var levels: AsyncStream<AudioLevels> {
        unclaimedLevels.withLock { stream in
            defer { stream = nil }
            return stream ?? AsyncStream { $0.finish() }
        }
    }

    private let unclaimedLevels: OSAllocatedUnfairLock<AsyncStream<AudioLevels>?>

    private let continuation: AsyncStream<AudioLevels>.Continuation
    private let state: OSAllocatedUnfairLock<State>

    public init?(
        bandCount: Int = AudioLevels.defaultBandCount,
        minimumInterval: Duration = defaultMinimumInterval,
    ) {
        guard let analyzer = AudioSpectrumAnalyzer(bandCount: bandCount) else { return nil }
        self.minimumInterval = minimumInterval
        state = OSAllocatedUnfairLock(
            uncheckedState: State(analyzer: analyzer, smoothed: Array(repeating: 0, count: bandCount)),
        )
        let (stream, continuation) = AsyncStream.makeStream(
            of: AudioLevels.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        unclaimedLevels = OSAllocatedUnfairLock(initialState: stream)
        self.continuation = continuation
    }

    /// Runs when ``levels`` ends — its consumer was cancelled or dropped the
    /// stream, or ``finish()`` ran. The place to remove this meter from its
    /// engine.
    public func onTermination(_ handler: @escaping @Sendable () -> Void) {
        continuation.onTermination = { _ in handler() }
    }

    /// Ends ``levels``.
    public func finish() {
        continuation.finish()
    }

    public func process(_ buffer: AVAudioPCMBuffer, at _: AVAudioTime?) {
        guard let frame = measure(buffer) else { return }
        continuation.yield(frame)
    }

    /// The frame to publish for `buffer`, or `nil` when the previous one went out
    /// less than ``minimumInterval`` before `now`, or `buffer` is unreadable.
    func measure(_ buffer: AVAudioPCMBuffer, at now: ContinuousClock.Instant = .now) -> AudioLevels? {
        state.withLockUnchecked { state in
            if let last = state.lastPublished, now - last < minimumInterval {
                return nil
            }
            guard let raw = state.analyzer.levels(for: buffer) else { return nil }
            state.smoothed = Self.smooth(previous: state.smoothed, next: raw.bands)
            state.lastPublished = now
            return AudioLevels(bands: state.smoothed)
        }
    }

    /// One step of the spec's ballistics.
    public static func smooth(previous: [Float], next: [Float]) -> [Float] {
        zip(previous, next).map { old, new in
            old + (new - old) * (new > old ? attack : release)
        }
    }
}
