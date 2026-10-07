import XCTest

/// Data that must survive the app being closed, and time-shifted launches.
final class PersistenceTests: StorySoundsUITestCase {

    // (10) Nickname and progress survive terminate + relaunch (no -uitest-reset, no -uitest-inmemory on relaunch).
    func testNicknameAndProgressSurviveRelaunch() {
        launchApp(inMemory: false)
        completeOnboarding(nameIndex: 2)
        let greeting = el("home.greeting").label
        XCTAssertTrue(greeting.hasPrefix("Hello,"), "Unexpected greeting '\(greeting)'")
        let stickers = stickerValue()
        XCTAssertTrue(stickers.hasPrefix("1"), "Expected the welcome sticker, got '\(stickers)'")

        relaunchKeepingData()
        XCTAssertTrue(el("home.start").waitForExistence(timeout: 20), "Relaunch should open Home, not onboarding")
        XCTAssertFalse(exists("onboarding.name.0"), "Onboarding must not return after relaunch")
        XCTAssertEqual(el("home.greeting").label, greeting, "Nickname did not persist")
        XCTAssertEqual(stickerValue(), stickers, "Stickers did not persist")
        XCTAssertTrue(waitForFocus(el("home.start")))
    }

    // (12) Delayed review: play a little, relaunch two days later, and the app still works with the time shift.
    // The session plan's reasons are not on screen, so this checks what IS observable (see NEEDS).
    func testRelaunchTwoDaysLaterStillPlaysAndShowsReviewCategory() {
        launchApp(inMemory: false)
        completeOnboarding()
        startSession()
        let out = drive(prefix: "session", terminals: ["summary.done"], maxCompletions: 3, maxSteps: 200)
        XCTAssertGreaterThanOrEqual(out.completions, 1, "Could not finish an activity (steps \(out.steps))")
        if !exists("summary.done") {
            press(.menu, settle: 0.8)
            XCTAssertTrue(el("session.menu.takeBreak").waitForExistence(timeout: 6))
            activate("session.menu.takeBreak", settle: 1.0)
        }
        if el("summary.done").waitForExistence(timeout: 4) { activate("summary.done", settle: 0.8) }
        XCTAssertTrue(el("home.start").waitForExistence(timeout: 10))

        relaunchKeepingData(extra: ["-uitest-day-offset", "2"])
        XCTAssertTrue(el("home.start").waitForExistence(timeout: 20), "Relaunch with a 2 day offset should open Home")
        // Observable review signal: the Skills page has a Review filter with a count.
        unlockParentArea()
        openParentSection("skills", ready: "parent.skills.cat.review")
        let label = el("parent.skills.cat.review").label
        XCTAssertTrue(label.hasPrefix("Review"), "Unexpected Review filter label '\(label)'")
        XCTContext.runActivity(named: "Review filter after +2 days: \(label)") { _ in }
        leaveParentToHome()
        startSession()
        XCTAssertTrue(el("session.progress").label.hasPrefix("Step 1 of"), "Progress label: \(el("session.progress").label)")
    }
}
