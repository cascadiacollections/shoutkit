import Foundation
import Observation
import RadioDirectory

@testable import Playback

// Shared doubles and builders for the PlaybackController test suites.

@MainActor
final class FakeAudioOutput: AudioOutput {
    var onStatusChange: ((AudioStatus) -> Void)?
    var onTrackInfo: ((AudioTrackInfo) -> Void)?

    private(set) var startedURLs: [URL] = []
    private(set) var stopCount = 0
    private(set) var resumeCount = 0

    var startedURL: URL? { startedURLs.last }
    var stopCalled: Bool { stopCount > 0 }

    func start(url: URL) { startedURLs.append(url) }
    func pause() { onStatusChange?(.paused) }
    func resume() {
        resumeCount += 1
        onStatusChange?(.playing)
    }
    func stop() { stopCount += 1 }
}

/// Spy standing in for the system now-playing surface, so tests never touch
/// `MPRemoteCommandCenter.shared()` and can assert exactly what the lock screen
/// was told, and when.
@MainActor
final class NowPlayingPresenterSpy: NowPlayingPresenting {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onToggle: (() -> Void)?

    enum Event: Equatable {
        case update(stationID: String, trackTitle: String?, isPlaying: Bool, artworkURL: URL?)
        case clear
    }

    private(set) var events: [Event] = []

    var lastUpdate: Event? { events.last(where: { $0 != .clear }) }

    func update(station: Station, track: NowPlayingMetadata?, isPlaying: Bool, artworkURL: URL?) {
        events.append(.update(
            stationID: station.id,
            trackTitle: track?.title,
            isPlaying: isPlaying,
            artworkURL: artworkURL
        ))
    }

    func clear() {
        events.append(.clear)
    }
}

func station(_ id: String = "kexp") -> Station {
    Station(
        id: id,
        name: "Station \(id)",
        genre: "Indie",
        listenerCount: 0,
        preferredStreamURL: URL(string: "https://example.com/\(id).aac")
    )
}

@MainActor
func makeController(
    stations: [Station],
    output: FakeAudioOutput,
    presenter: NowPlayingPresenterSpy = NowPlayingPresenterSpy(),
    pausedReleaseTimeout: Duration = .seconds(10 * 60),
    stallTimeout: Duration = .seconds(90),
    maxReconnectAttempts: Int = 3,
    reconnectBaseDelay: Duration = .seconds(2)
) -> PlaybackController {
    PlaybackController(
        directory: BundledRadioDirectory(stations: stations),
        output: output,
        nowPlayingCenter: presenter,
        pausedReleaseTimeout: pausedReleaseTimeout,
        stallTimeout: stallTimeout,
        maxReconnectAttempts: maxReconnectAttempts,
        reconnectBaseDelay: reconnectBaseDelay
    )
}

@MainActor
func waitForStart(_ output: FakeAudioOutput, count: Int = 1) async {
    for _ in 0..<200 where output.startedURLs.count < count {
        await Task.yield()
    }
}

func drainMainQueue() async {
    for _ in 0..<50 {
        await Task.yield()
    }
}

/// Polls until `condition` holds or the deadline passes (same pattern as
/// SleepTimerTests.waitUntilFired, shared here for the timeout-driven suites).
@MainActor
func waitUntil(_ condition: () -> Bool, upTo seconds: TimeInterval = 2) async {
    let deadline = Date().addingTimeInterval(seconds)
    while condition() == false, Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
final class ObservationToken {
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}

/// Registers a one-property observation and re-arms it after each change, so
/// tests can record a sequence of values using the macOS 15-compatible
/// `withObservationTracking` API. Call `cancel()` on the returned token when the
/// test is done to stop further recursive re-registration. Must be called from
/// MainActor context.
@MainActor
@discardableResult
func observeChanges<Value>(
    of value: @escaping @MainActor () -> Value,
    onChange: @escaping @MainActor (Value) -> Void
) -> ObservationToken {
    let token = ObservationToken()

    observeChanges(of: value, token: token, onChange: onChange)
    return token
}

@MainActor
private func observeChanges<Value>(
    of value: @escaping @MainActor () -> Value,
    token: ObservationToken,
    onChange: @escaping @MainActor (Value) -> Void
) {
    withObservationTracking {
        // Read once to register the dependency; the test only cares about
        // subsequent changes, so the initial value is intentionally ignored.
        _ = value()
    } onChange: {
        MainActor.assumeIsolated {
            // The tracked read above is MainActor-isolated, so re-entry here is
            // also on MainActor and `assumeIsolated` is safe.
            guard !token.isCancelled else { return }
            onChange(value())
            observeChanges(of: value, token: token, onChange: onChange)
        }
    }
}
