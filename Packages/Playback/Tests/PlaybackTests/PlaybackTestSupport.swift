import Foundation
import RadioDirectory

@testable import Playback

// Shared doubles and builders for the PlaybackController test suites.

@MainActor
final class FakeAudioOutput: AudioOutput {
    var onStatusChange: ((AudioStatus) -> Void)?
    var onTrackInfo: ((AudioTrackInfo) -> Void)?

    private(set) var startedURLs: [URL] = []
    private(set) var stopCalled = false

    var startedURL: URL? { startedURLs.last }

    func start(url: URL) { startedURLs.append(url) }
    func pause() { onStatusChange?(.paused) }
    func resume() { onStatusChange?(.playing) }
    func stop() { stopCalled = true }
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
    presenter: NowPlayingPresenterSpy = NowPlayingPresenterSpy()
) -> PlaybackController {
    PlaybackController(
        directory: BundledRadioDirectory(stations: stations),
        output: output,
        nowPlayingCenter: presenter
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
