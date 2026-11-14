import Foundation
@testable import NowPlayingActivityCore
import Testing

private func snapshot(
    station: String = "kexp",
    title: String? = "Song",
    token: String? = "abc",
    status: NowPlayingWidgetSnapshot.PlaybackStatus = .playing,
    at date: Date = Date(timeIntervalSince1970: 1_000_000),
) -> NowPlayingWidgetSnapshot {
    NowPlayingWidgetSnapshot(
        stationID: station,
        stationName: station.uppercased(),
        trackTitle: title,
        artist: "Artist",
        artworkToken: token,
        status: status,
        deepLinkURLString: "holmdel://station?id=\(station)",
        updatedAt: date,
    )
}

/// The widget must stop claiming a station is on air once the app has gone
/// quiet, and must ration background reloads to stay inside WidgetKit's budget.
struct NowPlayingWidgetSnapshotTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    @Test func `a playing or paused snapshot shows while fresh`() {
        #expect(snapshot(at: base).isShowable(at: base.addingTimeInterval(60)))
        #expect(snapshot(status: .paused, at: base).isShowable(at: base.addingTimeInterval(60)))
    }

    @Test func `a stopped snapshot never shows`() {
        #expect(snapshot(status: .stopped, at: base).isShowable(at: base) == false)
    }

    @Test func `a snapshot the app stopped refreshing expires`() {
        // The app was killed mid-stream and never wrote `.stopped`.
        let stale = base.addingTimeInterval(NowPlayingWidgetSnapshot.maximumAge)
        #expect(snapshot(at: base).isShowable(at: stale) == false)
        #expect(snapshot(at: base).expiresAt == stale)
    }
}

struct NowPlayingWidgetReloadPolicyTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)
    private let interval = NowPlayingWidgetReloadPolicy.minimumPausedReloadInterval

    private func decide(
        _ previous: NowPlayingWidgetSnapshot?,
        _ next: NowPlayingWidgetSnapshot,
        lastReload: Date?,
        after seconds: TimeInterval,
    ) -> NowPlayingWidgetReloadPolicy.Decision {
        NowPlayingWidgetReloadPolicy.decide(
            previous: previous,
            next: next,
            lastReload: lastReload,
            now: base.addingTimeInterval(seconds),
        )
    }

    private var settled: Date {
        base.addingTimeInterval(NowPlayingWidgetReloadPolicy.settleInterval)
    }

    @Test func `the first playing snapshot settles before reloading`() {
        #expect(decide(nil, snapshot(), lastReload: nil, after: 0) == .reloadAt(settled))
    }

    @Test func `a first stopped snapshot has nothing to replace`() {
        #expect(decide(nil, snapshot(status: .stopped), lastReload: nil, after: 0) == .skip)
    }

    @Test func `pause and stop reload immediately`() {
        let playing = snapshot()
        #expect(decide(playing, snapshot(status: .paused), lastReload: base, after: 0) == .reloadNow)
        #expect(decide(playing, snapshot(status: .stopped), lastReload: base, after: 0) == .reloadNow)
    }

    @Test func `starting playback and switching stations wait for album art`() {
        // The regression this pins: album art landed ten seconds after a station
        // switch and was pushed into the ten-minute window, so the widget showed
        // the station's art for ten minutes instead of the cover.
        #expect(decide(snapshot(status: .paused), snapshot(), lastReload: base, after: 0) == .reloadAt(settled))
        #expect(decide(snapshot(), snapshot(station: "wfmu"), lastReload: base, after: 0) == .reloadAt(settled))
    }

    @Test func `a heartbeat alone never reloads`() {
        let later = snapshot(at: base.addingTimeInterval(300))
        #expect(decide(snapshot(), later, lastReload: base, after: interval * 2) == .skip)
    }

    @Test func `while playing, track and artwork changes reload after settling`() {
        // Now Playing audio sessions reload budget-free, so a new track or its
        // cover must not wait out a rationing window.
        let next = snapshot(title: "Next Song", token: "def")
        #expect(decide(snapshot(), next, lastReload: base, after: 60) == .reloadAt(base.addingTimeInterval(
            60 + NowPlayingWidgetReloadPolicy.settleInterval,
        )))
    }

    @Test func `while paused, content changes are coalesced`() {
        let paused = snapshot(status: .paused)
        let next = snapshot(token: "def", status: .paused)
        #expect(decide(paused, next, lastReload: base, after: 60) == .reloadAt(base.addingTimeInterval(interval)))
    }
}

/// Isolated temp directory per test.
@Suite(.serialized)
struct NowPlayingWidgetStoreTests {
    @Test func `artwork token is deterministic and distinguishes URLs`() throws {
        let url = try #require(URL(string: "https://example.com/artwork.png"))
        let other = try #require(URL(string: "https://example.com/other.png"))
        #expect(NowPlayingWidgetStore.token(for: url) == NowPlayingWidgetStore.token(for: url))
        #expect(NowPlayingWidgetStore.token(for: url) != NowPlayingWidgetStore.token(for: other))
    }

    private func withTemporaryStore(_ body: () throws -> Void) rethrows {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        NowPlayingWidgetStore.directoryURLOverride = directory
        defer {
            NowPlayingWidgetStore.directoryURLOverride = nil
            try? FileManager.default.removeItem(at: directory)
        }
        try body()
    }

    @Test func `a saved snapshot round-trips`() throws {
        try withTemporaryStore {
            #expect(NowPlayingWidgetStore.load() == nil)
            let saved = snapshot()
            #expect(NowPlayingWidgetStore.save(saved))
            #expect(NowPlayingWidgetStore.load() == saved)
        }
    }

    @Test func `purging keeps the named artwork and the snapshot`() throws {
        try withTemporaryStore {
            NowPlayingWidgetStore.save(snapshot())
            #expect(NowPlayingWidgetStore.stageArtwork(Data([1]), forToken: "old"))
            #expect(NowPlayingWidgetStore.stageArtwork(Data([2]), forToken: "new"))

            NowPlayingWidgetStore.purgeArtwork(keeping: ["new"])

            #expect(NowPlayingWidgetStore.artworkFileURL(forToken: "old") == nil)
            #expect(NowPlayingWidgetStore.artworkFileURL(forToken: "new") != nil)
            #expect(NowPlayingWidgetStore.load() != nil)
        }
    }
}
