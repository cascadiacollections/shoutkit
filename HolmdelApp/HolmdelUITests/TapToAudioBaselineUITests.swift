import XCTest

/// Tap-to-audio for a station already in the listener's history.
///
/// The test plays the pinned station once first, then relaunches before every
/// iteration and times the tap until the player shows "Pause", which it does
/// once playback has started.
///
/// A live stream's start time varies with the network, so only a difference
/// that holds across runs means anything. Runs only from `Baselines.xctestplan`,
/// report-only. This class once measured the `prewarmStations` flag on and off;
/// the flag made no measurable difference and was deleted (`DECISIONS.md`,
/// 2026-11-14 and 2026-11-20).
final class TapToAudioBaselineUITests: XCTestCase {
    private static let pinnedStation = "KEXP 90.3 FM"

    /// Settle time after launch before the tap, kept from the prewarm comparison
    /// so the numbers stay comparable with earlier runs.
    private static let headStart: TimeInterval = 3

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedFirstRun", "YES"]
        return app
    }

    private func card(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", Self.pinnedStation))
            .firstMatch
    }

    private func pauseButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons["Pause"].firstMatch
    }

    /// Plays the pinned station once, so it's in Recently Played with a saved
    /// stream URL.
    @MainActor
    private func seedHistory() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(card(in: app).waitForExistence(timeout: 30), "Listen Now never showed \(Self.pinnedStation)")
        card(in: app).tap()
        guard pauseButton(in: app).waitForExistence(timeout: 30) else {
            throw XCTSkip("\(Self.pinnedStation) did not start playing within 30 s")
        }
        pauseButton(in: app).tap()
        app.terminate()
    }

    @MainActor
    private func measureTapToAudio() throws {
        try seedHistory()

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        var failedStarts = 0

        measure(metrics: [XCTClockMetric()], options: options) {
            let app = makeApp()
            app.launch()
            let station = card(in: app)
            _ = station.waitForExistence(timeout: 30)
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "head start")], timeout: Self.headStart)

            startMeasuring()
            station.tap()
            let started = pauseButton(in: app).waitForExistence(timeout: 30)
            stopMeasuring()

            if started == false {
                failedStarts += 1
            }
            app.terminate()
        }

        if failedStarts > 0 {
            throw XCTSkip("\(failedStarts) of 5 taps did not start playback within 30 s; the timings include them")
        }
    }

    @MainActor
    func testTapToAudio() throws {
        try measureTapToAudio()
    }
}
