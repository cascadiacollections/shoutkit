import ActivityKit
import Foundation

/// The now-playing Live Activity contract, shared between the app (which starts,
/// updates, and ends the activity) and the widget extension (which renders it).
///
/// Fixed attributes identify the station for the activity's lifetime; a station
/// switch ends the activity and starts a new one. The content state carries what
/// changes mid-stream: the live ICY track, play/pause state, and the current
/// artwork token.
///
/// Artwork can't be streamed inline — the content state is capped at 4 KB and
/// Live Activity views can't fetch network images — so the app downsamples the
/// current art into the shared App Group container (see ``LiveActivityArtworkStore``)
/// and passes only a small `artworkToken` here; the widget renders the file by
/// token. `nil` means "no art yet", so the widget falls back to a glyph.
public struct NowPlayingActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var trackTitle: String?
        public var artist: String?
        /// Opaque handle for the artwork the app has staged in the shared
        /// container. Resolve it with ``LiveActivityArtworkStore/fileURL(forToken:)``.
        public var artworkToken: String?
        public var isPlaying: Bool

        public init(
            trackTitle: String? = nil,
            artist: String? = nil,
            artworkToken: String? = nil,
            isPlaying: Bool
        ) {
            self.trackTitle = trackTitle
            self.artist = artist
            self.artworkToken = artworkToken
            self.isPlaying = isPlaying
        }
    }

    public var stationName: String
    public var genre: String

    public init(stationName: String, genre: String) {
        self.stationName = stationName
        self.genre = genre
    }
}
