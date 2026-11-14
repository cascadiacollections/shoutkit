import XCTest

/// Per-build launch and memory baselines (#148). Measured and reported, never
/// gated: there is no threshold until there's a trend to read, the same reasoning
/// as the coverage baseline.
///
/// Runs only from `Baselines.xctestplan`, which CI runs as its own report-only
/// step, so simulator noise or a radio stream that won't connect can't turn a
/// build red. The main test plan skips this class.
final class BaselineUITests: XCTestCase {
    /// Skips onboarding through the `@AppStorage("hasCompletedFirstRun")` key, so
    /// every iteration measures the app a returning listener sees.
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedFirstRun", "YES"]
        return app
    }

    /// KEXP is pinned to the top of Listen Now, so it's always there to wait on.
    private static let pinnedStation = "KEXP 90.3 FM"

    /// The pinned station's card, whatever element type SwiftUI exposes it as;
    /// its label starts with the station name.
    private func pinnedStationCard(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", Self.pinnedStation))
            .firstMatch
    }

    private func options(iterations: Int) -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = iterations
        return options
    }

    /// Time from launch until the app's first frame is responsive. Xcode
    /// terminates the app between iterations, so each is a fresh process; the
    /// summary reports the spread, not one figure, because simulator timings
    /// are noisy.
    @MainActor
    func testLaunchTime() {
        let app = makeApp()
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options(iterations: 5)) {
            app.launch()
        }
    }

    /// Memory from launch until Listen Now has stations on screen.
    @MainActor
    func testMemoryAfterLaunch() {
        let app = makeApp()
        measure(metrics: [XCTMemoryMetric(application: app)], options: options(iterations: 3)) {
            app.launch()
            _ = self.pinnedStationCard(in: app).waitForExistence(timeout: 30)
        }
    }

    /// Memory over a fixed stretch of playback. Skips rather than fails when the
    /// stream doesn't start, which on a CI runner usually means the network,
    /// not the app.
    @MainActor
    func testMemoryWhilePlaying() throws {
        let app = makeApp()
        app.launch()

        let station = pinnedStationCard(in: app)
        XCTAssertTrue(station.waitForExistence(timeout: 30), "Listen Now never showed \(Self.pinnedStation)")
        station.tap()

        let pause = app.buttons["Pause"].firstMatch
        guard pause.waitForExistence(timeout: 30) else {
            throw XCTSkip("\(Self.pinnedStation) did not start playing within 30 s")
        }

        measure(metrics: [XCTMemoryMetric(application: app)], options: options(iterations: 3)) {
            // Long enough for buffers, metadata and artwork to settle.
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "playback settles")], timeout: 10)
        }
    }
}
