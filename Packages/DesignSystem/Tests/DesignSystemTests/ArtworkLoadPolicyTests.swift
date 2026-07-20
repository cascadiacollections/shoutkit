import Foundation
import Testing

@testable import DesignSystem

struct ArtworkLoadPolicyTests {
    @Test
    func retriesPrimaryURLBeforeReturningLoadedArtwork() async throws {
        let primaryURL = try #require(URL(string: "https://example.com/album.jpg"))
        let request = ArtworkLoadRequest(primaryURL: primaryURL)
        var attempts = 0

        let loaded: Int? = await ArtworkLoadPolicy.load(
            request,
            retryDelays: [.zero, .zero]
        ) { _ in
            attempts += 1
            return attempts == 3 ? 7 : nil
        }

        #expect(loaded == 7)
        #expect(attempts == 3)
    }

    @Test
    func fallsBackToStationArtworkAfterPrimaryMisses() async throws {
        let primaryURL = try #require(URL(string: "https://example.com/album.jpg"))
        let fallbackURL = try #require(URL(string: "https://example.com/station.jpg"))
        let request = ArtworkLoadRequest(primaryURL: primaryURL, fallbackURL: fallbackURL)
        var primaryAttempts = 0
        var fallbackAttempts = 0

        let loaded = await ArtworkLoadPolicy.loadWithSource(
            request,
            retryDelays: [.zero]
        ) { url in
            if url == primaryURL {
                primaryAttempts += 1
                return nil
            }
            if url == fallbackURL {
                fallbackAttempts += 1
                return 42
            }
            return nil
        }

        #expect(loaded?.artwork == 42)
        #expect(loaded?.sourceURL == fallbackURL)
        #expect(primaryAttempts == 2)
        #expect(fallbackAttempts == 1)
    }
}
