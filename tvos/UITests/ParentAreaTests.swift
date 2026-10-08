import XCTest

/// Grown-ups' area: gate, settings, reset and delete.
final class ParentAreaTests: StorySoundsUITestCase {

    // (6a) Wrong answer shows a calm message and stays on a question; Menu leaves the gate.
    func testGateWrongAnswerShowsCalmMessageThenCorrectUnlocks() {
        launchApp(realHold: true)
        completeOnboarding()
        openParentGate()
        // A short press must not unlock.
        waitForFocus(el("parentgate.hold"))
        XCUIRemote.shared.press(.select, forDuration: 1.0)
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertTrue(el("parentgate.hold").exists, "A 1 s press should not pass the hold step")
        XCTAssertFalse(gatePromptElement().exists, "The question must not appear after a short press")

        passHoldStep()
        answerChallenge(correct: false)
        let notice = app.staticTexts["Not quite. Here is another question."]
        XCTAssertTrue(notice.waitForExistence(timeout: 6), "Calm wrong-answer message missing")
        assertCalmText([notice.label], context: "Gate notice")
        XCTAssertTrue(gatePromptElement().exists, "A new question should be shown")
        XCTAssertFalse(exists("parent.menu.progress"), "A wrong answer must not unlock")
        answerGateQuestions()   // two correct answers in a row unlock; each re-reads its own question
        XCTAssertTrue(el("parent.menu.progress").waitForExistence(timeout: 12), "Two correct answers should unlock")
    }

    // (6c) Two wrong answers start the calm lockout; the gate offers no way past it, and Back leaves.
    func testGateLocksAfterTwoWrongAnswers() {
        launchApp()
        completeOnboarding()
        openParentGate()
        passHoldStep()
        answerChallenge(correct: false)
        XCTAssertTrue(app.staticTexts["Not quite. Here is another question."].waitForExistence(timeout: 6))
        answerChallenge(correct: false)
        XCTAssertTrue(el("parentgate.locked").waitForExistence(timeout: 8), "Second wrong answer should lock the gate")
        XCTAssertFalse(exists("parent.menu.progress"))
        XCTAssertFalse(exists("parentgate.answer.0"), "No answers may be offered while locked")
        assertCalmText([el("parentgate.locked").label], context: "Gate lockout")
        activate("parentgate.back", settle: 0.8)
        XCTAssertTrue(el("home.start").waitForExistence(timeout: 8))
    }

    // (6d) "I can't hold the button": no hold, a harder 3-step question, still two correct answers.
    func testGateWithoutHoldUsesHarderQuestions() {
        launchApp(realHold: true)
        completeOnboarding()
        openParentGate()
        XCTAssertTrue(el("parentgate.nohold").waitForExistence(timeout: 8), "'I can't hold the button' missing")
        activate("parentgate.nohold", settle: 0.8)
        let prompt = gatePromptElement()
        XCTAssertTrue(prompt.waitForExistence(timeout: 8))
        XCTAssertTrue(prompt.label.hasPrefix("Multiply"), "Expected the 3-step variant, got '\(prompt.label)'")
        answerGateQuestions()
        XCTAssertTrue(el("parent.menu.progress").waitForExistence(timeout: 12), "Two correct hard answers should unlock")
    }

    // (6b) Hold + correct answer unlocks; Menu on the gate leaves to Home.
    func testGateMenuLeavesToHome() {
        launchApp()
        completeOnboarding()
        openParentGate()
        press(.menu, settle: 0.8)
        XCTAssertTrue(el("home.start").waitForExistence(timeout: 8), "Menu on the gate should return Home")
        openParentGate()
        activate("parentgate.back", settle: 0.8)
        XCTAssertTrue(el("home.start").waitForExistence(timeout: 8), "Back to Story Sounds should return Home")
    }

    // (7) Settings: +/- change session length and mastery thresholds; values persist across relaunch.
    func testSettingsStepsPersistAcrossRelaunch() {
        launchApp(inMemory: false)
        completeOnboarding()
        unlockParentArea()
        openParentSection("settings", ready: "parent.settings.session.minus")

        let session = staticText(beginningWith: "Session length is")
        XCTAssertTrue(session.waitForExistence(timeout: 6))
        let sessionBefore = session.label
        activate("parent.settings.session.minus", settle: 0.6)
        let sessionAfter = staticText(beginningWith: "Session length is").label
        XCTAssertNotEqual(sessionAfter, sessionBefore, "Minus should shorten the session (was '\(sessionBefore)')")

        pageForward("parent.settings", times: 2)
        XCTAssertTrue(el("parent.settings.mastery.attempts.plus").waitForExistence(timeout: 6), "Mastery page missing")
        let attemptsBefore = number(in: staticText(beginningWith: "Tries needed is").label)
        let scoreBefore = number(in: staticText(beginningWith: "Score needed is").label)
        activate("parent.settings.mastery.attempts.plus", settle: 0.6)
        activate("parent.settings.mastery.score.minus", settle: 0.6)
        let attemptsAfter = number(in: staticText(beginningWith: "Tries needed is").label)
        let scoreAfter = number(in: staticText(beginningWith: "Score needed is").label)
        XCTAssertEqual(attemptsAfter, attemptsBefore + 1, "Tries needed should go up by one")
        XCTAssertEqual(scoreAfter, scoreBefore - 5, "Score needed should go down by five points")

        leaveParentToHome()
        relaunchKeepingData()
        XCTAssertTrue(el("home.start").waitForExistence(timeout: 20), "Relaunch should open Home (profile persisted)")
        unlockParentArea()
        openParentSection("settings", ready: "parent.settings.session.minus")
        XCTAssertEqual(staticText(beginningWith: "Session length is").label, sessionAfter, "Session length did not persist")
        pageForward("parent.settings", times: 2)
        XCTAssertEqual(number(in: staticText(beginningWith: "Tries needed is").label), attemptsAfter, "Tries needed did not persist")
        XCTAssertEqual(number(in: staticText(beginningWith: "Score needed is").label), scoreAfter, "Score needed did not persist")
    }

    // (8) Reset progress: two-step confirm, Cancel is the default and keeps data, confirming resets.
    func testResetProgressTwoStepConfirm() {
        launchApp()
        completeOnboarding()
        let before = stickerValue()
        XCTAssertTrue(before.hasPrefix("1"), "Expected the welcome sticker before reset, got '\(before)'")
        unlockParentArea()
        openParentSection("data", ready: "parent.data.next")
        pageForward("parent.data", times: 3)

        // Cancel leaves data.
        activate("parent.data.reset", settle: 0.8)
        XCTAssertTrue(el("parent.data.cancel").waitForExistence(timeout: 8))
        XCTAssertTrue(waitForFocus(el("parent.data.cancel")), "Cancel must have default focus")
        press(.select, settle: 0.8)   // select Cancel
        XCTAssertTrue(el("parent.data.reset").waitForExistence(timeout: 6))
        leaveParentToHome()
        XCTAssertEqual(stickerValue(), before, "Cancel must leave progress untouched")

        // Confirm resets.
        activate("home.grownups", settle: 0.8)
        XCTAssertTrue(el("parentgate.back").waitForExistence(timeout: 8), "Parent gate did not appear")
        passHoldStep()
        answerGateQuestions()
        XCTAssertTrue(el("parent.menu.data").waitForExistence(timeout: 12))
        openParentSection("data", ready: "parent.data.next")
        pageForward("parent.data", times: 3)
        activate("parent.data.reset", settle: 0.8)
        XCTAssertTrue(el("parent.data.confirm").waitForExistence(timeout: 8))
        XCTAssertTrue(waitForFocus(el("parent.data.cancel")))
        activate("parent.data.confirm", settle: 1.0)
        XCTAssertTrue(el("parent.data.outcome").waitForExistence(timeout: 10), "Outcome message missing")
        XCTAssertFalse(el("parent.data.outcome").label.isEmpty)
        assertCalmText([el("parent.data.outcome").label], context: "Reset outcome")
        XCTAssertTrue(waitForFocus(el("parent.data.ok")), "OK should be focused")
        press(.select, settle: 0.8)
        leaveParentToHome()
        XCTAssertTrue(stickerValue().hasPrefix("0"), "Reset should clear stickers, got '\(stickerValue())'")
    }

    // (9) Delete everything returns to onboarding.
    func testDeleteEverythingReturnsToOnboarding() {
        launchApp()
        completeOnboarding()
        unlockParentArea()
        openParentSection("data", ready: "parent.data.next")
        pageForward("parent.data", times: 3)
        activate("parent.data.delete", settle: 0.8)
        XCTAssertTrue(el("parent.data.confirm").waitForExistence(timeout: 8), "Delete confirmation missing")
        XCTAssertTrue(waitForFocus(el("parent.data.cancel")), "Cancel must have default focus on the delete confirmation")
        activate("parent.data.confirm", settle: 1.0)
        XCTAssertTrue(el("parent.data.ok").waitForExistence(timeout: 10), "Outcome OK button missing")
        activate("parent.data.ok", settle: 1.0)
        let first = el("onboarding.name.0")
        XCTAssertTrue(first.waitForExistence(timeout: 12), "Deleting everything should return to onboarding")
        XCTAssertTrue(waitForFocus(first), "First name should be focused again")
    }

    /// First integer in a label such as "Score needed is 85%".
    private func number(in label: String) -> Int {
        let parts = label.split(whereSeparator: { !$0.isNumber })
        guard let first = parts.first, let n = Int(first) else {
            XCTFail("No number in '\(label)'")
            return -1
        }
        return n
    }
}
