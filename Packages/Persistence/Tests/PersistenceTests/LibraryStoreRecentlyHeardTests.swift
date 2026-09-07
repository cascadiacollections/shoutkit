import Foundation
import RadioDirectory
import SwiftData
import Testing

@testable import Persistence

@MainActor
struct LibraryStoreRecentlyHeardTests {
    private func makeStoreAndContext() -> (LibraryStore, ModelContext) {
        let container = ShoutKitModelContainer.makeContainer(inMemory: true)
        let context = ModelContext(container)
        return (LibraryStore(context: context), context)
    }

    private func station(_ id: String) -> Station {
        Station(id: id, name: "Station \(id)", genre: "Test", listenerCount: 10)
    }

    private func recentlyHeard(_ context: ModelContext) throws -> [RecentlyHeardTrack] {
        try context.fetch(
            FetchDescriptor<RecentlyHeardTrack>(
                sortBy: [SortDescriptor(\.heardAt, order: .reverse)]
            )
        )
    }

    @Test func loggingSameTrackConsecutivelyKeepsOneRecentlyHeardRow() throws {
        let (store, context) = makeStoreAndContext()
        let station = station("kexp")

        store.logRecentlyHeardTrack(station: station, title: "Song", artist: "Band")
        store.logRecentlyHeardTrack(station: station, title: "Song", artist: "Band")

        let rows = try recentlyHeard(context)
        #expect(rows.count == 1)
        #expect(rows.first?.title == "Song")
        #expect(rows.first?.artist == "Band")
    }

    @Test func loggingTrackAgainAfterDifferentTrackCreatesNewHistoryRow() throws {
        let (store, context) = makeStoreAndContext()
        let station = station("kexp")

        store.logRecentlyHeardTrack(station: station, title: "Song", artist: "Band")
        store.logRecentlyHeardTrack(station: station, title: "Other", artist: "Band")
        store.logRecentlyHeardTrack(station: station, title: "Song", artist: "Band")

        let rows = try recentlyHeard(context)
        #expect(rows.count == 3)
        #expect(rows.map(\.title) == ["Song", "Other", "Song"])
    }

    @Test func appleMusicLinkBackfillsMostRecentMatchingTrack() throws {
        let (store, context) = makeStoreAndContext()
        let station = station("kexp")
        let link = try #require(URL(string: "https://music.apple.com/us/album/song/1?i=2"))

        store.logRecentlyHeardTrack(station: station, title: "Song", artist: "Band")
        store.logRecentlyHeardTrack(station: station, title: "Song", artist: "Band", appleMusicURL: link)

        let rows = try recentlyHeard(context)
        #expect(rows.count == 1)
        #expect(rows.first?.appleMusicURLString == link.absoluteString)
    }

    @Test func artworkURLBackfillsMostRecentMatchingTrack() throws {
        let (store, context) = makeStoreAndContext()
        let station = station("kexp")
        let art = try #require(URL(string: "https://example.com/art/600x600bb.jpg"))

        store.logRecentlyHeardTrack(station: station, title: "Song", artist: "Band")
        store.logRecentlyHeardTrack(station: station, title: "Song", artist: "Band", artworkURL: art)

        let rows = try recentlyHeard(context)
        #expect(rows.count == 1)
        #expect(rows.first?.artworkURLString == art.absoluteString)
    }

    @Test func outOfOrderConsecutiveDuplicateDoesNotRegressHeardAt() throws {
        let (store, context) = makeStoreAndContext()
        let station = station("kexp")
        let latest = Date()
        let older = latest.addingTimeInterval(-90)

        store.logRecentlyHeardTrack(station: station, title: "Song", artist: "Band", heardAt: latest)
        store.logRecentlyHeardTrack(station: station, title: "Song", artist: "Band", heardAt: older)

        let rows = try recentlyHeard(context)
        #expect(rows.count == 1)
        #expect(rows.first?.heardAt == latest)
    }

    @Test func recentlyHeardIsCappedAtLimit() throws {
        let (store, context) = makeStoreAndContext()

        for index in 0..<(LibraryStore.recentlyHeardLimit + 20) {
            store.logRecentlyHeardTrack(
                station: station("s\(index)"),
                title: "Song \(index)",
                artist: "Band"
            )
        }

        let rows = try recentlyHeard(context)
        #expect(rows.count <= LibraryStore.recentlyHeardLimit)
    }

    @Test func recentlyHeardTrimClearsBacklogBeyondSingleBatch() throws {
        let (store, context) = makeStoreAndContext()
        let total = LibraryStore.recentlyHeardLimit + LibraryStore.recentlyHeardTrimHeadroom + 25

        for index in 0..<total {
            context.insert(
                RecentlyHeardTrack(
                    stationID: "seed\(index)",
                    stationName: "Seed \(index)",
                    title: "Song \(index)",
                    artist: "Band",
                    heardAt: .now.addingTimeInterval(TimeInterval(-index))
                )
            )
        }
        try context.save()

        store.logRecentlyHeardTrack(station: station("fresh"), title: "Fresh Song", artist: "Band")

        let rows = try recentlyHeard(context)
        #expect(rows.count <= LibraryStore.recentlyHeardLimit)
    }
}
