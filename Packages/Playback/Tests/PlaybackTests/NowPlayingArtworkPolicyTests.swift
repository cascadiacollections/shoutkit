import Foundation
import Testing

@testable import Playback

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
        ready: Set<URL> = []
    ) -> NowPlayingArtworkPolicy.Decision {
        NowPlayingArtworkPolicy.decide(
            artwork: artwork,
            stationArtworkURL: stationArtworkURL,
            presented: presented,
            isSameStation: isSameStation,
            readyArtworkURLs: ready
        )
    }

    // MARK: - Resolving

    @Test func resolvingFallsBackToStationArtOnFirstPush() {
        #expect(decide(artwork: .resolving, stationArtworkURL: stationArt) == .present(stationArt))
    }

    @Test func resolvingHoldsTheArtworkAlreadyOnScreen() {
        // The regression this exists to prevent: without the hold, every track
        // boundary snapped back to the station favicon for the length of the
        // lookup, so each song cost two artwork changes instead of one.
        #expect(
            decide(artwork: .resolving, stationArtworkURL: stationArt, presented: albumArt)
                == .present(albumArt)
        )
    }

    @Test func resolvingAfterAStationSwitchDropsTheOldStationsArt() {
        #expect(
            decide(
                artwork: .resolving,
                stationArtworkURL: stationArt,
                presented: albumArt,
                isSameStation: false
            ) == .present(stationArt)
        )
    }

    @Test func resolvingWithNothingToShowPresentsNothing() {
        #expect(decide(artwork: .resolving) == .present(nil))
    }

    // MARK: - Resolved

    @Test func resolvedArtworkAlreadyResidentIsPresentedImmediately() {
        #expect(
            decide(artwork: .resolved(nextAlbumArt), presented: albumArt, ready: [nextAlbumArt])
                == .present(nextAlbumArt)
        )
    }

    @Test func resolvedArtworkWithoutBytesHoldsUntilItIsFetched() {
        #expect(
            decide(artwork: .resolved(nextAlbumArt), presented: albumArt)
                == .hold(current: albumArt, pending: nextAlbumArt)
        )
    }

    @Test func resolvedNilFallsBackToStationArt() {
        #expect(
            decide(artwork: .resolved(nil), stationArtworkURL: stationArt, ready: [stationArt])
                == .present(stationArt)
        )
    }

    @Test func resolvedNilHoldsPreviousTrackArtOnlyUntilStationArtIsReady() {
        // A lookup miss must not strand the previous track's cover on screen…
        #expect(
            decide(artwork: .resolved(nil), stationArtworkURL: stationArt, presented: albumArt)
                == .hold(current: albumArt, pending: stationArt)
        )
        // …and the hold ends as soon as the station art can be served.
        #expect(
            decide(
                artwork: .resolved(nil),
                stationArtworkURL: stationArt,
                presented: albumArt,
                ready: [stationArt]
            ) == .present(stationArt)
        )
    }

    @Test func resolvedArtworkThatFailedToFetchIsAdvertisedAnyway() {
        // A URL marked ready-because-unfetchable releases the hold: the system's
        // own lazy provider gets a turn, and a stale image can't outlive the
        // track it belonged to.
        #expect(
            decide(artwork: .resolved(nextAlbumArt), presented: albumArt, ready: [nextAlbumArt])
                == .present(nextAlbumArt)
        )
    }

    @Test func resolvedArtworkAlreadyPresentedIsNotReadvertised() {
        #expect(decide(artwork: .resolved(albumArt), presented: albumArt) == .present(albumArt))
    }

    @Test func resolvedArtworkAfterAStationSwitchIsPresentedWithoutHolding() {
        #expect(
            decide(artwork: .resolved(albumArt), presented: nextAlbumArt, isSameStation: false)
                == .present(albumArt)
        )
    }

    @Test func resolvedNothingAtAllPresentsNothing() {
        #expect(decide(artwork: .resolved(nil), presented: albumArt) == .present(nil))
    }
}
