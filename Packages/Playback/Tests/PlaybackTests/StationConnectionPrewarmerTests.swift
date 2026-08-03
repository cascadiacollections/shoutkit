import Foundation
import Testing

@testable import Playback

/// Coverage for the conditions under which prewarming is skipped. The warming
/// itself opens real sockets, so it isn't exercised here — these cases assert
/// the cheap decisions made before any connection is attempted.
@Suite struct StationConnectionPrewarmerTests {
    @Test func lowPowerModeSkipsPrewarmingEntirely() async throws {
        let first = try #require(URL(string: "https://example.com/stream"))
        let second = try #require(URL(string: "https://other.example.com/stream"))
        let prewarmer = StationConnectionPrewarmer(
            handshakeTimeout: 0.01,
            isLowPowerModeEnabled: { true }
        )

        let warmed = await prewarmer.prewarm(streamURLs: [first, second])

        // Zero, not "fewer": prewarming is speculative in full, so conserving
        // means not spending the radio at all rather than warming a shorter list.
        #expect(warmed == 0)
    }

    @Test func noURLsIsANoOpEvenOutsideLowPowerMode() async {
        let prewarmer = StationConnectionPrewarmer(
            handshakeTimeout: 0.01,
            isLowPowerModeEnabled: { false }
        )

        let warmed = await prewarmer.prewarm(streamURLs: [])

        #expect(warmed == 0)
    }

    @Test func unusableURLsAreDroppedBeforeAnyConnectionIsAttempted() async {
        let prewarmer = StationConnectionPrewarmer(
            handshakeTimeout: 0.01,
            isLowPowerModeEnabled: { false }
        )

        // A file URL has no host, so no target can be built — nothing to warm,
        // and nothing that reaches the network even with prewarming enabled.
        let warmed = await prewarmer.prewarm(streamURLs: [URL(fileURLWithPath: "/tmp/not-a-stream")])

        #expect(warmed == 0)
    }
}
