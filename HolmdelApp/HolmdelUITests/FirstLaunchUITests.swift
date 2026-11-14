import XCTest

/// A fresh install must open to onboarding with no system prompt over it.
///
/// Holmdel asks for nothing at launch: motion access waits for Spatial Audio
/// (DECISIONS.md, 2026-11-14) and the app no longer uses location at all. This
/// is the check that would have caught the motion prompt #244 removed, which
/// shipped unnoticed because no test ever looked at a first launch.
///
/// XCTest rather than Swift Testing: UI automation is XCTest-only. It only proves
/// something on a fresh install, because a permission already answered never
/// prompts again, and there's no API to reset motion permission from here. CI's
/// simulator always installs fresh; locally, uninstall the app first or reset
/// with `xcrun simctl privacy booted reset all com.cascadiacollections.holmdel`.
final class FirstLaunchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testFirstLaunchShowsNoSystemAlert() {
        let app = XCUIApplication()
        app.launch()

        // Onboarding being up means launch finished, including the startup
        // restore of the Spatial Audio preference that used to trigger the prompt.
        XCTAssertTrue(
            app.buttons["Get Started"].waitForExistence(timeout: 20),
            "Onboarding never appeared",
        )

        // Permission prompts are drawn by SpringBoard, not the app. Give a late
        // one a moment to arrive before concluding there is none.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        XCTAssertFalse(
            alert.waitForExistence(timeout: 5),
            "A system alert appeared on first launch: \(alert.label)",
        )
    }
}
