#if canImport(NowPlaying)

import Foundation
import ImageIODownsample
import NowPlaying
import Observation
import RadioDirectory

/// iOS 27+ implementation of ``NowPlayingPresenting`` on the NowPlaying
/// framework — the WWDC26 replacement for the `MPNowPlayingInfoCenter`
/// dictionary + `MPRemoteCommandCenter` global-singleton pattern that
/// ``NowPlayingCenter`` bridges. A typed, observable `MediaSession` carries
/// `RadioContent` (purpose-built for live radio: station name, program line,
/// `duration: .live`) and structured `MediaCommand`s, and the system pulls
/// artwork through an async provider instead of our manual cache.
///
/// Selected at runtime by ``PlaybackController``'s production initializer;
/// iOS 26 devices keep the legacy `MediaPlayer` path.
@available(iOS 27, macOS 27, *)
@MainActor
public final class MediaSessionNowPlayingCenter: NowPlayingPresenting {
    public var onPlay: (() -> Void)?
    public var onPause: (() -> Void)?
    public var onStop: (() -> Void)?
    public var onToggle: (() -> Void)?

    /// The observable contract the system watches: content, playback snapshot,
    /// and available commands. `MediaSession` tracks changes via Observation.
    @Observable
    @MainActor
    final class SessionState: MediaSessionRepresentable {
        let id = "com.cascadiacollections.shoutkit.playback"
        var content: (any MediaContentRepresentable)?
        var playbackSnapshot: MediaPlaybackSnapshot?
        var commands: [MediaCommand] = []
    }

    private let state = SessionState()
    private var session: MediaSession<SessionState>?

    public init() {}

    public func update(station: Station, track: NowPlayingMetadata?, isPlaying: Bool, artworkURL: URL?) {
        if session == nil {
            state.commands = makeCommands()
            session = MediaSession(state)
        }

        // Prefer album art URL when provided; fall back to the station's own artwork.
        let targetArtworkURL = artworkURL ?? station.artworkURL

        var content = RadioContent(
            id: station.id,
            stationName: station.name,
            programName: programName(for: track),
            artwork: artwork(for: targetArtworkURL)
        )
        content.genre = station.genre.isEmpty ? nil : station.genre
        state.content = content
        state.playbackSnapshot = MediaPlaybackSnapshot(state: isPlaying ? .playing() : .paused)

        if isPlaying, let session, session.isApplicationPrimary == false {
            Task { try? await session.requestToBecomeApplicationPrimary() }
        }
    }

    public func clear() {
        state.content = nil
        state.playbackSnapshot = MediaPlaybackSnapshot(state: .stopped)
        // Dropping the session invalidates it and removes the entry from the
        // system surface; the next update() creates a fresh one.
        session = nil
    }

    /// "Title — Artist" as the program line under the station name.
    private func programName(for track: NowPlayingMetadata?) -> String? {
        let program = [track?.title, track?.artist].compactMap(\.self).joined(separator: " — ")
        return program.isEmpty ? nil : program
    }

    /// The system requests artwork lazily and caches by `Artwork.id`, so a
    /// station switch (new URL → new id) naturally invalidates old art — no
    /// manual cache-vs-station bookkeeping like the legacy path needed.
    private func artwork(for url: URL?) -> Artwork? {
        guard let url else { return nil }
        return Artwork(id: url.absoluteString) { @Sendable _ in
            let (data, _) = try await URLSession.shared.data(from: url)
            if let representation = try? ArtworkRepresentation(data: data) {
                return representation
            }
            guard let normalizedData = Self.normalizedArtworkData(from: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            return try ArtworkRepresentation(data: normalizedData)
        }
    }

    /// Some remote album-art payloads decode fine in ImageIO but are rejected by
    /// `ArtworkRepresentation(data:)`. Normalize through a decode + PNG re-encode
    /// so lock-screen Now Playing can still present the image.
    private nonisolated static func normalizedArtworkData(from data: Data) -> Data? {
        ImageIODownsampler.encode(data, maxPixelSize: 1024, outputType: .png)
    }

    /// Command callbacks arrive on arbitrary executors; hop to the main actor
    /// before touching the controller-facing closures.
    private func makeCommands() -> [MediaCommand] {
        [
            .play { [weak self] in await MainActor.run { self?.onPlay?() } },
            .pause { [weak self] in await MainActor.run { self?.onPause?() } },
            .stop { [weak self] in await MainActor.run { self?.onStop?() } },
            .togglePlayPause { [weak self] in await MainActor.run { self?.onToggle?() } },
        ]
    }
}

#endif
