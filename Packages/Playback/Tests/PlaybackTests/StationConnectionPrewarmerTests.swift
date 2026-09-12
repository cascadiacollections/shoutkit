import Foundation
@testable import Playback
import Testing

/// Coverage for the conditions under which prewarming is skipped. The warming
/// itself opens real sockets, so it isn't exercised here — these cases assert
/// the cheap decisions made before any connection is attempted.
struct StationConnectionPrewarmerTests {
    @Test func `low power mode skips prewarming entirely`() async throws {
        let first = try #require(URL(string: "https://example.com/stream"))
        let second = try #require(URL(string: "https://other.example.com/stream"))
        let prewarmer = StationConnectionPrewarmer(
            handshakeTimeout: 0.01,
            isLowPowerModeEnabled: { true },
        )

        let warmed = await prewarmer.prewarm(streamURLs: [first, second])

        // Zero, not "fewer": prewarming is speculative in full, so conserving
        // means not spending the radio at all rather than warming a shorter list.
        #expect(warmed == 0)
    }

    @Test func `no UR ls is A no op even outside low power mode`() async {
        let prewarmer = StationConnectionPrewarmer(
            handshakeTimeout: 0.01,
            isLowPowerModeEnabled: { false },
        )

        let warmed = await prewarmer.prewarm(streamURLs: [])

        #expect(warmed == 0)
    }

    @Test func `unusable UR ls are dropped before any connection is attempted`() async {
        let prewarmer = StationConnectionPrewarmer(
            handshakeTimeout: 0.01,
            isLowPowerModeEnabled: { false },
        )

        // A file URL has no host, so no target can be built — nothing to warm,
        // and nothing that reaches the network even with prewarming enabled.
        let warmed = await prewarmer.prewarm(streamURLs: [URL(fileURLWithPath: "/tmp/not-a-stream")])

        #expect(warmed == 0)
    }
}
