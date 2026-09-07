import Foundation
import Testing

@testable import Persistence

struct TopTracksAggregatorTests {
    private func track(
        title: String?,
        artist: String?,
        heardAt: Date,
        artworkURLString: String? = nil,
        appleMusicURLString: String? = nil
    ) -> RecentlyHeardTrack {
        RecentlyHeardTrack(
            stationID: "kexp",
            stationName: "KEXP",
            title: title,
            artist: artist,
            heardAt: heardAt,
            appleMusicURLString: appleMusicURLString,
            artworkURLString: artworkURLString
        )
    }

    @Test func countsRepeatedPlaysOfTheSameTrack() {
        let now = Date()
        let tracks = [
            track(title: "Song", artist: "Band", heardAt: now),
            track(title: "Song", artist: "Band", heardAt: now.addingTimeInterval(-60)),
            track(title: "Other", artist: "Band", heardAt: now.addingTimeInterval(-120))
        ]

        let top = TopTracksAggregator.aggregate(tracks, timeframe: .allTime, now: now)

        #expect(top.count == 2)
        #expect(top.first?.title == "Song")
        #expect(top.first?.playCount == 2)
    }

    @Test func matchingIsCaseInsensitiveOnTitleAndArtist() {
        let now = Date()
        let tracks = [
            track(title: "Song", artist: "Band", heardAt: now),
            track(title: "SONG", artist: "band", heardAt: now.addingTimeInterval(-60))
        ]

        let top = TopTracksAggregator.aggregate(tracks, timeframe: .allTime, now: now)

        #expect(top.count == 1)
        #expect(top.first?.playCount == 2)
    }

    @Test func tracksMissingTitleOrArtistAreExcluded() {
        let now = Date()
        let tracks = [
            track(title: "Song", artist: nil, heardAt: now),
            track(title: nil, artist: "Band", heardAt: now)
        ]

        let top = TopTracksAggregator.aggregate(tracks, timeframe: .allTime, now: now)

        #expect(top.isEmpty)
    }

    @Test func timeframeExcludesPlaysOutsideTheWindow() {
        let now = Date()
        let tracks = [
            track(title: "Recent", artist: "Band", heardAt: now.addingTimeInterval(-3600)),
            track(title: "Old", artist: "Band", heardAt: now.addingTimeInterval(-60 * 60 * 24 * 30))
        ]

        let top = TopTracksAggregator.aggregate(tracks, timeframe: .week, now: now)

        #expect(top.map(\.title) == ["Recent"])
    }

    @Test func mostRecentArtworkWinsWhenPlaysDisagree() {
        let now = Date()
        let olderArt = "https://example.com/old.jpg"
        let newerArt = "https://example.com/new.jpg"
        let tracks = [
            track(title: "Song", artist: "Band", heardAt: now, artworkURLString: newerArt),
            track(title: "Song", artist: "Band", heardAt: now.addingTimeInterval(-60), artworkURLString: olderArt)
        ]

        let top = TopTracksAggregator.aggregate(tracks, timeframe: .allTime, now: now)

        #expect(top.first?.artworkURLString == newerArt)
    }

    @Test func sortsByPlayCountThenRecency() {
        let now = Date()
        let tracks = [
            track(title: "Once", artist: "Band", heardAt: now),
            track(title: "Twice", artist: "Band", heardAt: now.addingTimeInterval(-60)),
            track(title: "Twice", artist: "Band", heardAt: now.addingTimeInterval(-120))
        ]

        let top = TopTracksAggregator.aggregate(tracks, timeframe: .allTime, now: now)

        #expect(top.map(\.title) == ["Twice", "Once"])
    }

    @Test func limitCapsTheReturnedRowCount() {
        let now = Date()
        let tracks = (0..<5).map { index in
            track(title: "Song \(index)", artist: "Band", heardAt: now.addingTimeInterval(TimeInterval(-index)))
        }

        let top = TopTracksAggregator.aggregate(tracks, timeframe: .allTime, limit: 2, now: now)

        #expect(top.count == 2)
    }
}
