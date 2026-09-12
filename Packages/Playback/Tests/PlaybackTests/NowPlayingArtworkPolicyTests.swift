import Foundation
@testable import Playback
import Testing

/// The artwork-identity decision behind ``NowPlayingPresenting``. Its whole job
/// is to keep artwork changes down to one per track with the image already in
/// hand, because on Bluetooth (AVRCP) each change costs a track-changed
/// notification plus a cover-art transfer the head unit may not finish in time.
struct NowPlayingArtworkPolicyTests {
    /// `force_unwrapping` is an error in this codebase and these are known-good
    /// literals, so the fallback is unreachable.
    private static func fixture(_ string: String) -> URL {
        URL(string: string) ?? URL(fileURLWithPath: "/")
    }

    private let stationArt = NowPlayingArtworkPolicyTests.fixture("https://example.com/station.png")
    private let albumArt = NowPlayingArtworkPolicyTests.fixture("https://example.com/album/600x600bb.jpg")
    private let nextAlbumArt = NowPlayingArtworkPolicyTests.fixture("https://example.com/album2/600x600bb.jpg")

    private func decide(
        artwork: NowPlayingArtwork,
        stationArtworkURL: URL? = nil,
        presented: URL? = nil,
        isSameStation: Bool = true,
        ready: Set<URL> = [],
    ) -> NowPlayingArtworkPolicy.Decision {
        NowPlayingArtworkPolicy.decide(
            artwork: artwork,
            stationArtworkURL: stationArtworkURL,
            presented: presented,
            isSameStation: isSameStation,
            readyArtworkURLs: ready,
        )
    }

    // MARK: - Resolving

    @Test func `resolving on first push fetches station art before advertising it`() {
        // Cold start: nothing is held and the station's bytes aren't in hand, so
        // there is nothing to advertise yet. Advertising the URL here would spend
        // the head unit's single cover-art request on a lazy network fetch.
        #expect(
            decide(artwork: .resolving, stationArtworkURL: stationArt)
                == .hold(current: nil, pending: stationArt),
        )
    }

    @Test func `resolving presents station art once its bytes are ready`() {
        #expect(
            decide(artwork: .resolving, stationArtworkURL: stationArt, ready: [stationArt])
                == .present(stationArt),
        )
    }

    @Test func `resolving holds the artwork already on screen`() {
        // The regression this exists to prevent: without the hold, every track
        // boundary snapped back to the station favicon for the length of the
        // lookup, so each song cost two artwork changes instead of one.
        #expect(
            decide(artwork: .resolving, stationArtworkURL: stationArt, presented: albumArt)
                == .present(albumArt),
        )
    }

    @Test func `resolving after A station switch drops the old stations art`() {
        // Nothing from the previous station is worth holding, and the new
        // station's art still has to be fetched before it can be advertised.
        #expect(
            decide(
                artwork: .resolving,
                stationArtworkURL: stationArt,
                presented: albumArt,
                isSameStation: false,
            ) == .hold(current: nil, pending: stationArt),
        )
        #expect(
            decide(
                artwork: .resolving,
                stationArtworkURL: stationArt,
                presented: albumArt,
                isSameStation: false,
                ready: [stationArt],
            ) == .present(stationArt),
        )
    }

    @Test func `resolving with nothing to show presents nothing`() {
        #expect(decide(artwork: .resolving) == .present(nil))
    }

    // MARK: - Resolved

    @Test func `resolved artwork already resident is presented immediately`() {
        #expect(
            decide(artwork: .resolved(nextAlbumArt), presented: albumArt, ready: [nextAlbumArt])
                == .present(nextAlbumArt),
        )
    }

    @Test func `resolved artwork without bytes holds until it is fetched`() {
        #expect(
            decide(artwork: .resolved(nextAlbumArt), presented: albumArt)
                == .hold(current: albumArt, pending: nextAlbumArt),
        )
    }

    @Test func `resolved nil falls back to station art`() {
        #expect(
            decide(artwork: .resolved(nil), stationArtworkURL: stationArt, ready: [stationArt])
                == .present(stationArt),
        )
    }

    @Test func `resolved nil holds previous track art only until station art is ready`() {
        // A lookup miss must not strand the previous track's cover on screen…
        #expect(
            decide(artwork: .resolved(nil), stationArtworkURL: stationArt, presented: albumArt)
                == .hold(current: albumArt, pending: stationArt),
        )
        // …and the hold ends as soon as the station art can be served.
        #expect(
            decide(
                artwork: .resolved(nil),
                stationArtworkURL: stationArt,
                presented: albumArt,
                ready: [stationArt],
            ) == .present(stationArt),
        )
    }

    @Test func `resolved artwork that failed to fetch is advertised anyway`() {
        // A URL marked ready-because-unfetchable releases the hold: the system's
        // own lazy provider gets a turn, and a stale image can't outlive the
        // track it belonged to.
        #expect(
            decide(artwork: .resolved(nextAlbumArt), presented: albumArt, ready: [nextAlbumArt])
                == .present(nextAlbumArt),
        )
    }

    @Test func `resolved artwork already presented is not readvertised`() {
        #expect(decide(artwork: .resolved(albumArt), presented: albumArt) == .present(albumArt))
    }

    @Test func `resolved artwork after A station switch holds nothing but still waits for bytes`() {
        #expect(
            decide(artwork: .resolved(albumArt), presented: nextAlbumArt, isSameStation: false)
                == .hold(current: nil, pending: albumArt),
        )
        #expect(
            decide(
                artwork: .resolved(albumArt),
                presented: nextAlbumArt,
                isSameStation: false,
                ready: [albumArt],
            ) == .present(albumArt),
        )
    }

    @Test func `resolved nothing at all presents nothing`() {
        #expect(decide(artwork: .resolved(nil), presented: albumArt) == .present(nil))
    }

    /// The Tesla regression: a station with no artwork of its own has nothing
    /// presented yet (`held == nil`) by the time the first track's album art
    /// resolves — but that is still the same station, not a switch, so the
    /// unfetched art must not be advertised before its bytes exist.
    @Test func `resolved first track art on A station with no artwork of its own holds until fetched`() {
        #expect(
            decide(artwork: .resolved(albumArt))
                == .hold(current: nil, pending: albumArt),
        )
    }

    @Test func `resolved first track art is presented once its bytes are resident`() {
        #expect(
            decide(artwork: .resolved(albumArt), ready: [albumArt])
                == .present(albumArt),
        )
    }
}
