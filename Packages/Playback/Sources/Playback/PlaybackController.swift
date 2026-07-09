import Foundation
import Observation
import RadioDirectory

/// App-wide, observable playback state. Injected through the SwiftUI environment so
/// the mini-player, Now Playing screen, and every station row read and drive the same
/// playback. Owns the ``AudioOutput`` and mirrors its status into ``PlaybackState``.
@MainActor
@Observable
public final class PlaybackController {
    public private(set) var state: PlaybackState = .idle

    public private(set) var nowPlaying: NowPlayingMetadata?
    public private(set) var isAdPlaying = false
    public private(set) var isLoadingAmbientFallback = false
    public private(set) var ambientFallbackError: String?

    /// Invoked whenever a station is chosen for playback. The app layer uses this
    /// to log recents so Playback does not depend on the persistence layer.
    /// (An event hook, deliberately — `state`/`nowPlaying` are @Observable and
    /// consumers follow them with `Observations`; a play is a discrete action.)
    @ObservationIgnored public var onStationPlayed: ((Station) -> Void)?

    public var currentStation: Station? { activeStation }

    @ObservationIgnored private var activeStation: Station?
    @ObservationIgnored private let directory: any RadioDirectoryProviding
    @ObservationIgnored private let output: any AudioOutput
    @ObservationIgnored private let nowPlayingCenter: any NowPlayingPresenting
    @ObservationIgnored private var resolveTask: Task<Void, Never>?

    /// Whether `output.start` has run for the active station. False while the
    /// stream endpoint is still resolving, or after a pause during loading —
    /// in that case `resume()` must re-play rather than resume a nonexistent player.
    @ObservationIgnored private var outputStarted = false

    /// Set when the system interrupts playback that was active, so playback can
    /// resume automatically when the interruption ends with a resume hint.
    @ObservationIgnored private var resumeAfterInterruption = false

    /// Designated initializer with every collaborator explicit — what tests use.
    /// The iOS production defaults live in the convenience initializer below so
    /// this type (and its tests) build on platforms without AVAudioSession/UIKit.
    public init(
        directory: any RadioDirectoryProviding,
        output: any AudioOutput,
        nowPlayingCenter: any NowPlayingPresenting
    ) {
        self.directory = directory
        self.output = output
        self.nowPlayingCenter = nowPlayingCenter

        configureOutput()
        configureRemoteCommands()
    }

    #if canImport(UIKit)
    /// Production wiring: AVPlayer-backed audio and the system now-playing center.
    /// On iOS 27+ the now-playing surface is the NowPlaying framework's typed
    /// MediaSession; iOS 26 keeps the legacy MediaPlayer bridge. Both sit behind
    /// ``NowPlayingPresenting``, so nothing else changes with the OS version.
    public convenience init(directory: any RadioDirectoryProviding) {
        let nowPlayingCenter: any NowPlayingPresenting
        #if canImport(NowPlaying)
        if #available(iOS 27, *) {
            nowPlayingCenter = MediaSessionNowPlayingCenter()
        } else {
            nowPlayingCenter = NowPlayingCenter()
        }
        #else
        nowPlayingCenter = NowPlayingCenter()
        #endif

        self.init(
            directory: directory,
            output: AVPlayerAudioOutput(),
            nowPlayingCenter: nowPlayingCenter
        )
    }
    #endif

    // MARK: - Intents

    public func play(_ station: Station) {
        resolveTask?.cancel()
        activeStation = station
        state = .loading(station)
        nowPlaying = nil
        isAdPlaying = false
        isLoadingAmbientFallback = false
        ambientFallbackError = nil
        outputStarted = false
        resumeAfterInterruption = false
        onStationPlayed?(station)

        resolveTask = Task { [weak self] in
            guard let self else { return }
            do {
                let endpoint = try await directory.streamEndpoint(for: station)
                guard Task.isCancelled == false, self.activeStation?.id == station.id else { return }
                self.output.start(url: endpoint.url)
                self.outputStarted = true
                self.nowPlayingCenter.update(station: station, track: nil, isPlaying: true)
            } catch {
                guard Task.isCancelled == false, self.activeStation?.id == station.id else { return }
                self.state = .failed(error.localizedDescription)
                self.activeStation = nil
                self.isAdPlaying = false
            }
        }
    }

    public func pause() {
        // Pausing while the stream endpoint is still resolving must cancel the
        // pending start, or audio would begin after the user asked it not to.
        if case let .loading(station) = state {
            resolveTask?.cancel()
            state = .paused(station)
            nowPlayingCenter.update(station: station, track: nowPlaying, isPlaying: false)
            return
        }
        output.pause()
    }

    public func resume() {
        guard let station = activeStation else { return }

        switch state {
        case .paused:
            if outputStarted {
                output.resume()
            } else {
                // Paused during loading: the player never started, so re-play.
                play(station)
            }
        case .failed:
            play(station)
        default:
            break
        }
    }

    /// Toggles play/pause for the currently active station.
    public func togglePlayPause() {
        switch state {
        case .playing, .buffering, .loading:
            pause()
        case .paused, .failed:
            resume()
        case .idle:
            break
        }
    }

    /// Plays the station if it isn't the active one; otherwise toggles play/pause.
    public func toggle(_ station: Station) {
        if activeStation?.id == station.id {
            togglePlayPause()
        } else {
            play(station)
        }
    }

    public func stop() {
        resolveTask?.cancel()
        output.stop()
        activeStation = nil
        state = .idle
        nowPlaying = nil
        isAdPlaying = false
        isLoadingAmbientFallback = false
        ambientFallbackError = nil
        outputStarted = false
        resumeAfterInterruption = false
        nowPlayingCenter.clear()
    }

    public func playAmbientFallback() async {
        guard isAdPlaying, isLoadingAmbientFallback == false else { return }

        isLoadingAmbientFallback = true
        ambientFallbackError = nil
        let currentStationID = activeStation?.id
        let fallback = await ambientFallbackStation(excluding: currentStationID)
        isLoadingAmbientFallback = false

        guard let fallback else {
            ambientFallbackError = "No ambient fallback is available right now."
            return
        }

        play(fallback)
    }

    // MARK: - Per-station phase

    public func phase(for station: Station) -> StationPlaybackPhase {
        guard activeStation?.id == station.id else { return .idle }

        switch state {
        case .loading, .buffering:
            return .loading
        case .playing:
            return .playing
        case .paused:
            return .paused
        case let .failed(message):
            return .failed(message)
        case .idle:
            return .idle
        }
    }

    // MARK: - Wiring

    private func configureOutput() {
        output.onStatusChange = { [weak self] status in
            guard let self, let station = self.activeStation else { return }
            switch status {
            case .buffering:
                self.state = .buffering(station)
            case .playing:
                self.state = .playing(station)
                self.nowPlayingCenter.update(station: station, track: self.nowPlaying, isPlaying: true)
            case .paused:
                self.state = .paused(station)
                self.nowPlayingCenter.update(station: station, track: self.nowPlaying, isPlaying: false)
            case let .failed(message):
                self.state = .failed(message)
            case .interruptionBegan:
                self.handleInterruptionBegan(station: station)
            case let .interruptionEnded(shouldResume):
                if self.resumeAfterInterruption, shouldResume {
                    self.resume()
                }
                self.resumeAfterInterruption = false
            }
        }

        output.onTrackInfo = { [weak self] info in
            guard let self, let station = self.activeStation else { return }
            if info.isAdvertisement {
                self.isAdPlaying = true
                self.nowPlaying = nil
                let isPlaying = if case .playing = self.state { true } else { false }
                self.nowPlayingCenter.update(station: station, track: nil, isPlaying: isPlaying)
                return
            }

            self.isAdPlaying = false
            let metadata = NowPlayingMetadata(
                stationID: station.id,
                title: info.title,
                artist: info.artist,
                receivedAt: Date()
            )
            self.nowPlaying = metadata

            let isPlaying = if case .playing = self.state { true } else { false }
            self.nowPlayingCenter.update(station: station, track: metadata, isPlaying: isPlaying)
        }
    }

    private func handleInterruptionBegan(station: Station) {
        switch state {
        case .playing, .buffering:
            // The system already paused the player; remember to resume.
            resumeAfterInterruption = true
            state = .paused(station)
        case .loading:
            // Don't let a pending start fire mid-interruption.
            resumeAfterInterruption = true
            resolveTask?.cancel()
            outputStarted = false
            state = .paused(station)
        default:
            break
        }
        nowPlayingCenter.update(station: station, track: nowPlaying, isPlaying: false)
    }

    private func configureRemoteCommands() {
        nowPlayingCenter.onPlay = { [weak self] in self?.resume() }
        nowPlayingCenter.onPause = { [weak self] in self?.pause() }
        nowPlayingCenter.onStop = { [weak self] in self?.stop() }
        nowPlayingCenter.onToggle = { [weak self] in self?.togglePlayPause() }
    }

    private func ambientFallbackStation(excluding stationID: Station.ID?) async -> Station? {
        for genre in ["Ambient", "Nature"] {
            if let station = try? await directory.stations(inGenre: genre, limit: 5)
                .first(where: { $0.id != stationID }) {
                return station
            }
        }

        for query in ["ambient", "nature", "sleep", "meditation"] {
            if let station = try? await directory.searchStations(matching: query, limit: 5)
                .first(where: { $0.id != stationID }) {
                return station
            }
        }

        return nil
    }
}

#if canImport(UIKit)
public extension PlaybackController {
    /// A controller wired to preview data for SwiftUI previews.
    @MainActor
    static func preview() -> PlaybackController {
        PlaybackController(directory: PreviewRadioDirectory())
    }
}
#endif
