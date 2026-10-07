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
}
