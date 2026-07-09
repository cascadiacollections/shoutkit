import Foundation
import RadioDirectory

@testable import Playback

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

/// Directory whose discovery calls block until `open()` is called, so tests
/// can interleave user actions with an in-flight ambient-fallback lookup.
/// `streamEndpoint` stays ungated — `play()` must keep working while the
/// lookup is suspended.
actor GatedRadioDirectory: RadioDirectoryProviding {
    private let base: BundledRadioDirectory
    private var isOpen = false

    init(stations: [Station]) {
        base = BundledRadioDirectory(stations: stations)
    }

    func open() { isOpen = true }

    func genres() async throws(RadioDirectoryError) -> [Genre] {
        try await base.genres()
    }

    func topStations(limit: Int) async throws(RadioDirectoryError) -> [Station] {
        try await base.topStations(limit: limit)
    }

    func searchStations(matching query: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        await waitForGate()
        return try await base.searchStations(matching: query, limit: limit)
    }

    func stations(inGenre genre: String, limit: Int) async throws(RadioDirectoryError) -> [Station] {
        await waitForGate()
        return try await base.searchStations(matching: genre, limit: limit)
    }

    func streamEndpoint(for station: Station) async throws(RadioDirectoryError) -> StreamEndpoint {
        try await base.streamEndpoint(for: station)
    }

    private func waitForGate() async {
        while isOpen == false { await Task.yield() }
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
        case update(stationID: String, trackTitle: String?, isPlaying: Bool)
        case clear
    }

    private(set) var events: [Event] = []

    var lastUpdate: Event? { events.last(where: { $0 != .clear }) }

    func update(station: Station, track: NowPlayingMetadata?, isPlaying: Bool) {
        events.append(.update(stationID: station.id, trackTitle: track?.title, isPlaying: isPlaying))
    }

    func clear() {
        events.append(.clear)
    }
}
