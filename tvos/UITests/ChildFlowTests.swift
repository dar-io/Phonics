import XCTest

/// Child-facing flows: onboarding, baseline, a whole lesson, the break overlay, the "do it together" help,
/// Reduce Motion and silent (captions only) play.
final class ChildFlowTests: StorySoundsUITestCase {

    // (1) First launch -> onboarding focused -> choose a name -> baseline intro -> play baseline -> Home.
    func testFirstLaunchOnboardingThenBaselinePlayedReachesHome() {
        launchApp()
        let first = el("onboarding.name.0")
        XCTAssertTrue(first.waitForExistence(timeout: 20), "Onboarding did not appear")
        XCTAssertTrue(waitForFocus(first), "First name should have focus on launch")
        assertFocus("Onboarding")
        completeOnboarding(nameIndex: 1, playBaseline: true)
        let greeting = el("home.greeting")
        XCTAssertTrue(greeting.waitForExistence(timeout: 5))
        XCTAssertTrue(greeting.label.hasPrefix("Hello,"), "Unexpected greeting: \(greeting.label)")
        XCTAssertTrue(el("home.start").hasFocus)
    }

    // (1b) Baseline can be skipped.
    func testBaselineSkipReachesHomeWithStartFocused() {
        launchApp()
        completeOnboarding(nameIndex: 0, playBaseline: false)
        XCTAssertTrue(el("home.start").hasFocus)
        XCTAssertFalse(exists("onboarding.name.0"))
    }

    // (2) A full lesson to a calm summary.
    func testFullLessonEndsInCalmSummary() {
        // One-minute sessions (4 activities) and a fixed seed keep this fast and repeatable on CI.
        launchApp(extra: ["-uitest-session-minutes", "1", "-uitest-seed", "7"])
        completeOnboarding()
        startSession()
        var feedbackTexts: [String] = []
        let out = drive(prefix: "session", terminals: ["summary.done", "session.empty.home"], maxSteps: 700,
                        stopWhen: { [self] in
            let f = el("session.feedback")
            if f.exists { feedbackTexts.append(f.label) }
            return false
        })
        guard out.foundTerminal == "summary.done" else {
            XCTFail("Lesson did not reach the summary (terminal: \(out.foundTerminal ?? "none"), steps: \(out.steps), completions: \(out.completions))")
            return
        }
        XCTAssertGreaterThanOrEqual(out.completions, 3, "Expected several activities to be finished")
        XCTAssertTrue(el("summary.title").exists)
        XCTAssertTrue(el("summary.title").label.hasPrefix("Lovely work"), "Summary title: \(el("summary.title").label)")
        XCTAssertTrue(el("summary.message").exists)
        assertCalmText(allVisibleTexts(), context: "Summary")
        assertCalmText(feedbackTexts, context: "Feedback banners")
        XCTAssertTrue(waitForFocus(el("summary.done")), "Done should be focused on the summary")
        activate("summary.done", settle: 0.8)
        XCTAssertTrue(el("home.start").waitForExistence(timeout: 10), "Done should return to Home")
    }

    // (3) Menu mid-session: break overlay, Keep playing focused, Menu keeps playing, focus restored, leave -> Home.
    func testMenuMidSessionShowsBreakOverlayAndFocusIsRestored() {
        launchApp()
        completeOnboarding()
        startSession()
        let before = { [self] () -> String in
            for _ in 0..<10 {
                let id = focusedIdentifier()
                if !id.isEmpty { return id }
                Thread.sleep(forTimeInterval: 0.3)
            }
            return ""
        }()
        XCTAssertFalse(before.isEmpty, "Expected a focused control on the first activity")

        press(.menu, settle: 0.8)
        let keep = el("session.menu.continue")
        XCTAssertTrue(keep.waitForExistence(timeout: 6), "Break overlay did not appear")
        XCTAssertTrue(app.staticTexts["Take a break?"].exists, "Overlay title 'Take a break?' missing")
        XCTAssertTrue(waitForFocus(keep), "'Keep playing' should have focus in the overlay")
        assertFocus("Break overlay")

        press(.menu, settle: 0.8)
        XCTAssertTrue(keep.waitForNonExistence(timeout: 6), "Menu inside the overlay should keep playing")
        XCTAssertTrue(el("session.prompt").exists, "Activity should still be on screen")
        let deadline = Date().addingTimeInterval(5)
        var restored = ""
        while Date() < deadline {
            restored = focusedIdentifier()
            if restored == before { break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertEqual(restored, before, "Focus should return to where it was before the overlay")

        press(.menu, settle: 0.8)
        XCTAssertTrue(keep.waitForExistence(timeout: 6))
        activate("session.menu.takeBreak", settle: 1.0)
        let home = el("home.start")
        let done = el("summary.done")
        let deadline2 = Date().addingTimeInterval(10)
        while Date() < deadline2 && !home.exists && !done.exists { Thread.sleep(forTimeInterval: 0.3) }
        if done.exists { activate("summary.done", settle: 0.8) }
        XCTAssertTrue(home.waitForExistence(timeout: 10), "Taking a break should return to Home")
    }

    // (4) Struggle: two wrong choices in one activity -> "sound it out together" steps, learner can still finish.
    func testTwoMissesShowModelledStepsAndLearnerCanFinish() {
        // `-uitest-first-choice-wrong` (DEBUG only) puts the correct choice last, so Select on the focused choice
        // misses twice in a row in every choice-based activity. No skip: if it never happens the test fails.
        launchApp(extra: ["-uitest-first-choice-wrong", "-uitest-session-minutes", "1", "-uitest-seed", "7"])
        completeOnboarding()
        startSession()
        // The check requires the feedback banner AND the modelled panel together, which only happens after two
        // misses (a plan-started modelled activity has no feedback yet).
        let out = drive(prefix: "session", terminals: ["summary.done", "session.empty.home"], maxSteps: 300,
                        stopWhen: { [self] in exists("session.model.text") && exists("session.feedback") })
        guard out.stopped else {
            XCTFail("No activity produced two misses in a row (steps \(out.steps), terminal: \(out.foundTerminal ?? "none"))")
            return
        }
        let model = el("session.model.text")
        XCTAssertFalse(model.label.isEmpty, "Modelled step text is empty")
        let feedback = el("session.feedback")
        assertCalmText([feedback.label, model.label], context: "Struggle feedback")
        XCTAssertTrue(exists("session.model.next"), "Modelled panel needs its next-step button")
        XCTAssertTrue(waitForFocus(el("session.model.next")), "Modelled step button should be focused")

        let finish = drive(prefix: "session", terminals: ["session.next", "summary.done"], maxSteps: 120)
        XCTAssertNotNil(finish.foundTerminal, "Learner could not finish the helped activity (steps \(finish.steps))")
        if finish.foundTerminal == "session.next" {
            XCTAssertFalse(el("session.feedback").label.isEmpty)
            assertCalmText([el("session.feedback").label], context: "Completion feedback")
            activate("session.next", settle: 0.8)
        }
    }

    // (11) Reduce Motion: navigation still works with no animation dependencies.
    func testReduceMotionStillNavigates() {
        launchApp(extra: ["-uitest-reduce-motion"])
        completeOnboarding()
        activate("home.stickers", settle: 0.8)
        XCTAssertTrue(el("stickers.back").waitForExistence(timeout: 8), "Sticker book did not open")
        assertFocus("Sticker book (reduce motion)")
        press(.menu, settle: 0.8)
        XCTAssertTrue(el("home.start").waitForExistence(timeout: 8))
        startSession()
        let out = drive(prefix: "session", terminals: ["summary.done"], maxCompletions: 2, maxSteps: 200)
        XCTAssertGreaterThanOrEqual(out.completions, 2, "Two activities should finish under Reduce Motion (steps \(out.steps))")
        press(.menu, settle: 0.8)
        XCTAssertTrue(el("session.menu.continue").waitForExistence(timeout: 6), "Overlay should appear under Reduce Motion")
        press(.menu, settle: 0.8)
        XCTAssertTrue(el("session.prompt").waitForExistence(timeout: 6))
    }

    // (13) Audio disabled: the prompt is always shown as text; sound captions appear when a sound is "played".
    func testNoAudioStillShowsCaptions() {
        launchApp()
        completeOnboarding()
        startSession()
        let prompt = el("session.prompt")
        XCTAssertFalse(prompt.label.trimmingCharacters(in: .whitespaces).isEmpty, "Prompt caption is empty")
        XCTAssertTrue(exists("session.hearAgain"), "Hear-it-again control should exist even without audio")
        // Soft check: poll for the sound caption (about 4.5 s) while playing a few activities.
        var sawSoundCaption = exists("session.soundCaption")
        var rounds = 0
        while !sawSoundCaption && rounds < 6 {
            rounds += 1
            let out = drive(prefix: "session", terminals: ["summary.done"], maxCompletions: 1, maxSteps: 60,
                            stopWhen: { [self] in exists("session.soundCaption") })
            if out.stopped || exists("session.soundCaption") { sawSoundCaption = true }
            if out.foundTerminal != nil { break }
            XCTAssertTrue(el("session.prompt").waitForExistence(timeout: 8) || exists("summary.done"))
            if exists("session.prompt") {
                XCTAssertFalse(el("session.prompt").label.isEmpty, "Prompt caption missing on a later activity")
            }
        }
        if sawSoundCaption {
            XCTAssertTrue(el("session.soundCaption").label.hasPrefix("Sound"), "Caption: \(el("session.soundCaption").label)")
        } else {
            XCTContext.runActivity(named: "No sound caption observed in \(rounds) activities (activities without phoneme audio show none)") { _ in }
        }
    }
}
