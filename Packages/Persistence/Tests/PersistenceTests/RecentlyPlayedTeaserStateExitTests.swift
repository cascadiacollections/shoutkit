// Exit tests run the body in a child process, so they exist only where Swift
// Testing can spawn one: the mac host (`swift test`), not the iOS simulator,
// where this suite also runs from the test plan. See DECISIONS.md 2026-11-13.
#if os(macOS) || os(Linux) || os(Windows)
    @testable import Persistence
    import Testing

    struct RecentlyPlayedTeaserStateExitTests {
        /// The precondition is the type's only guard against a teaser that could
        /// never show anything, and nothing exercised it until exit tests could.
        @Test func `a non-positive capacity traps`() async {
            await #expect(processExitsWith: .failure) {
                _ = RecentlyPlayedTeaserState(capacity: 0)
            }
        }
    }
#endif
