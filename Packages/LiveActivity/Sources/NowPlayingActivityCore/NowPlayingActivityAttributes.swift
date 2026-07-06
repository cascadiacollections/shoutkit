import ActivityKit
import Foundation

/// The now-playing Live Activity contract, shared between the app (which starts,
/// updates, and ends the activity) and the widget extension (which renders it).
///
/// Fixed attributes identify the station for the activity's lifetime; a station
/// switch ends the activity and starts a new one. The content state carries what
/// changes mid-stream: the live ICY track and play/pause state.
///
/// Deliberately no artwork: Live Activity views cannot load network images, and
/// shipping them would require an App Group hand-off that this milestone scoped out.
public struct NowPlayingActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var trackTitle: String?
        public var artist: String?
        public var isPlaying: Bool

        public init(trackTitle: String? = nil, artist: String? = nil, isPlaying: Bool) {
            self.trackTitle = trackTitle
            self.artist = artist
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
