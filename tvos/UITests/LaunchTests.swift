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

    // Unreadable progress offers a second, quiet option. Retry stays the default focus; Start fresh needs a two-step
    // confirm with Cancel focused first, and Cancel returns to the first step (nothing is created or deleted).
    func testUnreadableProgressShowsStartFreshWithRetryDefaultAndSafeConfirm() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-inmemory", "-uitest-no-audio", "-uitest-force-load-error"]
        app.launch()
        let retry = app.buttons["loaderror.retry"]
        let startFresh = app.buttons["loaderror.startfresh"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        XCTAssertTrue(startFresh.exists, "Start fresh should be offered next to Retry")
        var deadline = Date().addingTimeInterval(5)
        while Date() < deadline && !retry.hasFocus { Thread.sleep(forTimeInterval: 0.25) }
        XCTAssertTrue(retry.hasFocus, "Retry should be the default focus")
        XCUIRemote.shared.press(.down)
        deadline = Date().addingTimeInterval(3)
        while Date() < deadline && !startFresh.hasFocus { Thread.sleep(forTimeInterval: 0.25) }
        XCTAssertTrue(startFresh.hasFocus)
        XCUIRemote.shared.press(.select)
        let cancel = app.buttons["loaderror.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["loaderror.confirm"].exists)
        deadline = Date().addingTimeInterval(5)
        while Date() < deadline && !cancel.hasFocus { Thread.sleep(forTimeInterval: 0.25) }
        XCTAssertTrue(cancel.hasFocus, "Cancel should be focused by default in the confirm step")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["loaderror.retry"].waitForExistence(timeout: 5), "Cancel returns to the first step")
    }
}
