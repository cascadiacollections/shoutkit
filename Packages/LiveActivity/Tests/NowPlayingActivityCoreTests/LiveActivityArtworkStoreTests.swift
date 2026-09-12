import Foundation
@testable import NowPlayingActivityCore
import Testing

struct LiveActivityArtworkStoreTests {
    @Test
    func `token is deterministic for URL`() throws {
        let url = try #require(URL(string: "https://example.com/artwork.png"))
        #expect(LiveActivityArtworkStore.token(for: url) == LiveActivityArtworkStore.token(for: url))
    }

    @Test
    func `stage overwrites existing token file`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        LiveActivityArtworkStore.directoryURLOverride = directory
        defer {
            LiveActivityArtworkStore.purge()
            try? FileManager.default.removeItem(at: directory)
            LiveActivityArtworkStore.directoryURLOverride = nil
        }

        let token = "shared"
        #expect(LiveActivityArtworkStore.stage(Data([1, 2, 3]), forToken: token) == token)
        #expect(LiveActivityArtworkStore.stage(Data([4, 5, 6]), forToken: token) == token)
        let fileURL = try #require(LiveActivityArtworkStore.fileURL(forToken: token))
        #expect((try? Data(contentsOf: fileURL)) == Data([4, 5, 6]))
    }

    @Test
    func `purge removes stale tokens and keeps current one`() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        LiveActivityArtworkStore.directoryURLOverride = directory
        defer {
            LiveActivityArtworkStore.purge()
            try? FileManager.default.removeItem(at: directory)
            LiveActivityArtworkStore.directoryURLOverride = nil
        }

        #expect(LiveActivityArtworkStore.stage(Data([1]), forToken: "old") == "old")
        #expect(LiveActivityArtworkStore.stage(Data([2]), forToken: "current") == "current")

        LiveActivityArtworkStore.purge(except: "current")

        #expect(LiveActivityArtworkStore.fileURL(forToken: "old") == nil)
        #expect(LiveActivityArtworkStore.fileURL(forToken: "current") != nil)
    }

    @Test
    func `purge keeping retains every listed token and drops the rest`() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        LiveActivityArtworkStore.directoryURLOverride = directory
        defer {
            LiveActivityArtworkStore.purge()
            try? FileManager.default.removeItem(at: directory)
            LiveActivityArtworkStore.directoryURLOverride = nil
        }

        #expect(LiveActivityArtworkStore.stage(Data([1]), forToken: "applied") == "applied")
        #expect(LiveActivityArtworkStore.stage(Data([2]), forToken: "pending") == "pending")
        #expect(LiveActivityArtworkStore.stage(Data([3]), forToken: "stale") == "stale")

        LiveActivityArtworkStore.purge(keeping: ["applied", "pending"])

        #expect(LiveActivityArtworkStore.fileURL(forToken: "applied") != nil)
        #expect(LiveActivityArtworkStore.fileURL(forToken: "pending") != nil)
        #expect(LiveActivityArtworkStore.fileURL(forToken: "stale") == nil)

        LiveActivityArtworkStore.purge(keeping: [])

        #expect(LiveActivityArtworkStore.fileURL(forToken: "applied") == nil)
        #expect(LiveActivityArtworkStore.fileURL(forToken: "pending") == nil)
    }
}
