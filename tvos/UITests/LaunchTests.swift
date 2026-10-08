import XCTest

final class LaunchTests: XCTestCase {
    func testFirstLaunchShowsOnboardingWithFocusedChoice() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-inmemory", "-uitest-no-audio"]
        app.launch()
        let first = app.buttons["onboarding.name.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        XCTAssertTrue(first.hasFocus)
    }

    // The friendly recovery screen must render (it once crashed for lack of an AppEnvironment) with Retry focused,
    // and Retry must lead on to the app once the fault is gone (the flag is dropped on retry).
    func testForcedLoadErrorShowsRetryFocusedAndRetryRecovers() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-inmemory", "-uitest-no-audio", "-uitest-force-load-error"]
        app.launch()
        let retry = app.buttons["loaderror.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15), "Load-error screen did not appear (or the app crashed)")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "loaderror.message").firstMatch.exists)
        XCTAssertFalse(retry.label.isEmpty)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && !retry.hasFocus { Thread.sleep(forTimeInterval: 0.25) }
        XCTAssertTrue(retry.hasFocus, "Retry should be focused")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["onboarding.name.0"].waitForExistence(timeout: 15), "Retry should continue to onboarding")
    }
}
