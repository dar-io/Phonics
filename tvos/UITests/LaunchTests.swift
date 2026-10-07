import XCTest

final class LaunchTests: XCTestCase {
    func testLaunchShowsFocusedStartButton() {
        let app = XCUIApplication()
        app.launch()
        let start = app.buttons["start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(start.hasFocus)
    }
}
