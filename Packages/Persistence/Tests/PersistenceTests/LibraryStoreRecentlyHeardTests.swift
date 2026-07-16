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
}
