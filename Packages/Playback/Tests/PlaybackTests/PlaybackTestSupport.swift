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
    private(set) var startedStreamGenerations: [UInt64] = []
    private(set) var stopCount = 0
    private(set) var resumeCount = 0
    private(set) var pauseCount = 0

    /// When true, `resume()` reports nothing back — standing in for a streaming
    /// engine that quietly refuses to resume a player whose stream is already
    /// gone (AudioStreaming's `resume()` no-ops unless its own state is exactly
    /// `.paused`; `AVPlayer.play()` does nothing for an ended item). This is the
    /// case the controller's resume watchdog exists for.
    var resumeSilentlyFails = false

    var startedURL: URL? { startedURLs.last }
    var stopCalled: Bool { stopCount > 0 }

    func start(url: URL, streamGeneration: UInt64) {
        startedURLs.append(url)
        startedStreamGenerations.append(streamGeneration)
    }
    func pause() {
        pauseCount += 1
        onStatusChange?(.paused)
    }
    func resume() {
        resumeCount += 1
        guard resumeSilentlyFails == false else { return }
        onStatusChange?(.playing)
    }
    func stop() { stopCount += 1 }

    func emitTrackInfo(_ title: String?, _ artist: String?) {
        let generation = startedStreamGenerations.last ?? 0
        onTrackInfo?(AudioTrackInfo(title: title, artist: artist, streamGeneration: generation))
    }
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

/// Directory that counts `streamEndpoint(for:)` calls, so tests can assert the
/// controller reuses a resolved endpoint across reconnects instead of
/// re-resolving each attempt.
actor CountingRadioDirectory: RadioDirectoryProviding {
    private(set) var streamEndpointCallCount = 0
    private let base: BundledRadioDirectory

    init(stations: [Station]) {
        base = BundledRadioDirectory(stations: stations)
    }

    func topStations(limit: Int) async throws(RadioDirectoryError) -> [Station] {
        try await base.topStations(limit: limit)
    }

    func genres() async throws(RadioDirectoryError) -> [Genre] {
        try await base.genres()
    }

    func stations(inGenre genre: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        try await base.stations(inGenre: genre, limit: limit)
    }

    func searchStations(matching query: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        try await base.searchStations(matching: query, limit: limit)
    }

    func streamEndpoint(for station: Station) async throws(RadioDirectoryError) -> StreamEndpoint {
        streamEndpointCallCount += 1
        return try await base.streamEndpoint(for: station)
    }
}

@MainActor
func makeController(
    directory: any RadioDirectoryProviding,
    output: FakeAudioOutput,
    presenter: NowPlayingPresenterSpy = NowPlayingPresenterSpy(),
    maxReconnectAttempts: Int = 3,
    reconnectBaseDelay: Duration = .seconds(2),
    resumeWatchdogTimeout: Duration = .seconds(2),
    hintlessResumeWindow: Duration = .seconds(90)
) -> PlaybackController {
    PlaybackController(
        directory: directory,
        output: output,
        nowPlayingCenter: presenter,
        maxReconnectAttempts: maxReconnectAttempts,
        reconnectBaseDelay: reconnectBaseDelay,
        resumeWatchdogTimeout: resumeWatchdogTimeout,
        hintlessResumeWindow: hintlessResumeWindow
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
    reconnectBaseDelay: Duration = .seconds(2),
    resumeWatchdogTimeout: Duration = .seconds(2),
    hintlessResumeWindow: Duration = .seconds(90)
) -> PlaybackController {
    PlaybackController(
        directory: BundledRadioDirectory(stations: stations),
        output: output,
        nowPlayingCenter: presenter,
        pausedReleaseTimeout: pausedReleaseTimeout,
        stallTimeout: stallTimeout,
        maxReconnectAttempts: maxReconnectAttempts,
        reconnectBaseDelay: reconnectBaseDelay,
        resumeWatchdogTimeout: resumeWatchdogTimeout,
        hintlessResumeWindow: hintlessResumeWindow
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
    withObservationTracking({
        // Read once to register the dependency; the test only cares about
        // subsequent changes, so the initial value is intentionally ignored.
        _ = value()
    }, onChange: {
        // `onChange` fires before the triggering mutation is actually applied,
        // so reading `value()` synchronously here would still observe the old
        // value. Hop through a Task so the read lands after the mutation.
        Task { @MainActor in
            guard !token.isCancelled else { return }
            onChange(value())
            observeChanges(of: value, token: token, onChange: onChange)
        }
    })
}
