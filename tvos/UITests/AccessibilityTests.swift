import XCTest

/// Representative accessibility checks. Multiple TV resolutions are covered by the CI device matrix (a test cannot
/// resize the tvOS simulator).
final class AccessibilityTests: StorySoundsUITestCase {

    func testHomeAndParentMenuElementsHaveLabels() {
        launchApp()
        XCTAssertTrue(el("onboarding.name.0").waitForExistence(timeout: 20))
        assertLabelled("Onboarding")
        completeOnboarding()
        assertLabelled("Home")
        for id in ["home.start", "home.stickers", "home.sound", "home.gentle", "home.grownups"] {
            XCTAssertFalse(el(id).label.isEmpty, "\(id) has an empty accessibility label")
        }
        unlockParentArea()
        assertLabelled("Parent menu")
        for s in ["progress", "practice", "skills", "audio", "settings", "data", "leave"] {
            XCTAssertFalse(el("parent.menu.\(s)").label.isEmpty, "parent.menu.\(s) has an empty accessibility label")
        }
    }

    private func assertLabelled(_ context: String) {
        let buttons = app.buttons.allElementsBoundByIndex
        XCTAssertFalse(buttons.isEmpty, "\(context): expected focusable buttons")
        for b in buttons {
            XCTAssertFalse(b.label.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(context): button '\(b.identifier)' has an empty label")
        }
        for t in app.staticTexts.allElementsBoundByIndex {
            XCTAssertFalse(t.label.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(context): static text '\(t.identifier)' has an empty label")
        }
    }
}
