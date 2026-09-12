import Foundation
@testable import PlayerFeatureCore
import Testing

struct EffectiveArtworkTests {
    private let albumArt = URL(string: "https://example.com/album.jpg")
    private let stationArt = URL(string: "https://example.com/station.png")

    @Test func `album art wins and falls back to the station`() {
        let selection = EffectiveArtwork.selection(
            isAlbumArtEnabled: true,
            albumArtURL: albumArt,
            stationArtworkURL: stationArt,
        )

        #expect(selection.primaryURL == albumArt)
        #expect(selection.fallbackURL == stationArt)
    }

    /// The privacy toggle has to mean what it says on the surfaces too: turning
    /// album art off must not leave already-resolved album art on screen.
    @Test func `disabling album art ignores an already resolved URL`() {
        let selection = EffectiveArtwork.selection(
            isAlbumArtEnabled: false,
            albumArtURL: albumArt,
            stationArtworkURL: stationArt,
        )

        #expect(selection.primaryURL == stationArt)
        #expect(selection.fallbackURL == nil)
    }

    @Test func `enabled but unresolved falls back to the station as primary`() {
        let selection = EffectiveArtwork.selection(
            isAlbumArtEnabled: true,
            albumArtURL: nil,
            stationArtworkURL: stationArt,
        )

        #expect(selection.primaryURL == stationArt)
        #expect(selection.fallbackURL == nil)
    }

    /// The station's artwork is never also its own fallback. A loader that
    /// retried the identical URL would spend a second request to fail the same
    /// way — and, on the now-playing path, hold the previous track's image while
    /// it did (see DECISIONS.md 2026-08-06).
    @Test func `the station artwork is never its own fallback`() {
        for enabled in [true, false] {
            let selection = EffectiveArtwork.selection(
                isAlbumArtEnabled: enabled,
                albumArtURL: nil,
                stationArtworkURL: stationArt,
            )

            #expect(selection.fallbackURL != selection.primaryURL)
        }
    }

    @Test func `no artwork anywhere selects nothing rather than guessing`() {
        let selection = EffectiveArtwork.selection(
            isAlbumArtEnabled: true,
            albumArtURL: nil,
            stationArtworkURL: nil,
        )

        #expect(selection.primaryURL == nil)
        #expect(selection.fallbackURL == nil)
    }

    /// A station with no artwork of its own must not suppress album art — the
    /// album-art branch has to stay reachable when the fallback is empty.
    @Test func `album art still shows when the station has no artwork`() {
        let selection = EffectiveArtwork.selection(
            isAlbumArtEnabled: true,
            albumArtURL: albumArt,
            stationArtworkURL: nil,
        )

        #expect(selection.primaryURL == albumArt)
        #expect(selection.fallbackURL == nil)
    }
}
