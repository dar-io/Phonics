import XCTest

/// Focus-only navigation: something is always focused, no direction press loses focus, and Menu goes up exactly one
/// level and puts focus back on the control that opened the screen.
/// The simulator cannot be resized inside a test; the other TV resolutions are covered by the CI device matrix.
final class FocusNavigationTests: StorySoundsUITestCase {

    func testHomeAlwaysHasFocus() {
        launchApp()
        completeOnboarding()
        assertFocus("Home")
        XCTAssertTrue(el("home.start").hasFocus, "home.start should be the default focus")
        assertDirectionsKeepFocus("Home")
        // Every secondary button can be reached from the primary one.
        for id in ["home.stickers", "home.sound", "home.gentle", "home.grownups"] {
            focusElement(el(id))
            assertFocus("Home on \(id)")
        }
        focusElement(el("home.start"))
        XCTAssertTrue(el("home.start").hasFocus)
    }

    func testStickerBookMenuReturnsToOpener() {
        launchApp()
        completeOnboarding()
        activate("home.stickers", settle: 0.8)
        XCTAssertTrue(el("stickers.back").waitForExistence(timeout: 8))
        XCTAssertTrue(waitForFocus(el("stickers.back")), "Back should be focused in the sticker book")
        assertFocus("Sticker book")
        assertDirectionsKeepFocus("Sticker book")
        press(.menu, settle: 0.8)
        XCTAssertTrue(el("home.start").waitForExistence(timeout: 8), "Menu should close the sticker book")
        XCTAssertTrue(waitForFocus(el("home.stickers")), "Focus should return to the Sticker book button")
        assertFocus("Home after sticker book")
    }

    func testParentMenuAndSectionPageRestoreFocusToOpener() {
        launchApp(realHold: true)
        completeOnboarding()
        openParentGate()
        assertFocus("Parent gate (hold)")
        XCTAssertTrue(el("parentgate.hold").hasFocus, "Hold control should be focused first")
        assertDirectionsKeepFocus("Parent gate hold")
        // Back to a known state on the hold control before holding.
        focusElement(el("parentgate.hold"))
        passHoldStep()
        assertFocus("Parent gate (question)")
        XCTAssertTrue(waitForFocus(el("parentgate.answer.0")), "First answer should be focused")
        assertDirectionsKeepFocus("Parent gate question")
        answerGateQuestions()
        XCTAssertTrue(el("parent.menu.progress").waitForExistence(timeout: 12))
        assertFocus("Parent menu")
        assertDirectionsKeepFocus("Parent menu")

        activate("parent.menu.practice", settle: 0.8)
        XCTAssertTrue(el("parent.practice.next").waitForExistence(timeout: 8))
        assertFocus("Parent section page")
        assertDirectionsKeepFocus("Parent section page")
        press(.menu, settle: 0.8)
        XCTAssertTrue(el("parent.menu.practice").waitForExistence(timeout: 8), "Menu should go back to the parent menu")
        XCTAssertTrue(waitForFocus(el("parent.menu.practice")), "Focus should return to the card that opened the section")

        press(.menu, settle: 0.8)
        XCTAssertTrue(el("home.start").waitForExistence(timeout: 8), "Menu on the parent menu should leave to Home")
        assertFocus("Home after leaving parent area")
    }

    func testSettingsPageFocusAndMenuRestoresOpener() {
        launchApp()
        completeOnboarding()
        unlockParentArea()
        openParentSection("settings", ready: "parent.settings.session.minus")
        assertFocus("Settings page 1")
        assertDirectionsKeepFocus("Settings page 1")
        activate("parent.settings.next", settle: 0.8)
        XCTAssertTrue(el("parent.settings.volume.narration.minus").waitForExistence(timeout: 6), "Volume page missing")
        assertFocus("Settings page 2")
        assertDirectionsKeepFocus("Settings page 2")
        press(.menu, settle: 0.8)
        XCTAssertTrue(waitForFocus(el("parent.menu.settings")), "Focus should return to the Settings card")
    }

    func testDataConfirmScreenFocusDefaultsToCancelAndMenuCancels() {
        launchApp()
        completeOnboarding()
        unlockParentArea()
        openParentSection("data", ready: "parent.data.next")
        pageForward("parent.data", times: 3)
        XCTAssertTrue(el("parent.data.reset").waitForExistence(timeout: 6), "Reset page missing")
        assertFocus("Data reset page")
        activate("parent.data.reset", settle: 0.8)
        XCTAssertTrue(el("parent.data.cancel").waitForExistence(timeout: 8), "Confirm screen did not appear")
        XCTAssertTrue(waitForFocus(el("parent.data.cancel")), "Cancel must be the default focus")
        assertFocus("Confirm screen")
        assertDirectionsKeepFocus("Confirm screen")
        // Make sure we are back on a known control, then Menu cancels the action (one level up).
        press(.menu, settle: 0.8)
        XCTAssertTrue(el("parent.data.cancel").waitForNonExistence(timeout: 6), "Menu should cancel the confirmation")
        XCTAssertTrue(el("parent.data.reset").waitForExistence(timeout: 6), "Should return to the reset page")
        assertFocus("Data reset page after cancel")
        press(.menu, settle: 0.8)
        XCTAssertTrue(waitForFocus(el("parent.menu.data")), "Focus should return to the Your data card")
    }
}
