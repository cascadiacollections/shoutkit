import XCTest

/// Tap-to-audio with the `prewarmStations` flag off and on: the measurement the
/// flag's promote-or-delete decision (#146) was waiting on.
///
/// Prewarming warms only stations in the listener's history (favorites, then
/// recents with a saved stream URL), so on a fresh install it has nothing to do.
/// Each test therefore plays the pinned station once first, then relaunches
/// before every iteration and times the tap until the player shows "Pause", which
/// it does once playback has started. The launch warmup gets the same head start
/// in both variants.
///
/// Read the two results as a pair, from the same run: a live stream's start time
/// varies with the network far more than a DNS lookup and a TLS handshake do, so
/// only a difference that holds across runs means anything. Runs only from
/// `Baselines.xctestplan`, report-only.
final class TapToAudioBaselineUITests: XCTestCase {
    private static let pinnedStation = "KEXP 90.3 FM"

    /// Time the launch warmup gets before the tap, the same with and without it.
    private static let headStart: TimeInterval = 3

    private func makeApp(prewarm: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedFirstRun", "YES",
            // DefaultsFeatureFlagService reads `featureFlags.<key>.override`;
            // a launch argument sets it for this run only.
            "-featureFlags.prewarmStations.override", prewarm ? "enabled" : "disabled",
        ]
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
    /// stream URL: what prewarming warms.
    @MainActor
    private func seedHistory() throws {
        let app = makeApp(prewarm: false)
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
    private func measureTapToAudio(prewarm: Bool) throws {
        try seedHistory()

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        var failedStarts = 0

        measure(metrics: [XCTClockMetric()], options: options) {
            let app = makeApp(prewarm: prewarm)
            app.launch()
            let station = card(in: app)
            _ = station.waitForExistence(timeout: 30)
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "warmup head start")], timeout: Self.headStart)

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
    func testTapToAudioWithoutPrewarm() throws {
        try measureTapToAudio(prewarm: false)
    }

    @MainActor
    func testTapToAudioWithPrewarm() throws {
        try measureTapToAudio(prewarm: true)
    }
}
