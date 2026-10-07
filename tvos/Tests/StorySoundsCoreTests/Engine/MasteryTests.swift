import XCTest
@testable import StorySoundsCore

final class MasteryTests: XCTestCase {
    private let settings: MasterySettings = MasterySettings()
    private func fresh() -> SkillState { return SkillState(unitId: "g-s", track: .recognise) }

    // MARK: Evidence thresholds (just below / just above)

    func testFullEvidenceBecomesSecure() {
        let s: SkillState = secureSkill("g-s", .recognise)
        XCTAssertEqual(s.status, .secure)
        XCTAssertTrue(Mastery.isSecure(s, settings: settings))
        XCTAssertNotNil(s.secureAt)
        XCTAssertEqual(s.attempts, 8)
        XCTAssertEqual(s.independentCorrect, 8)
    }

    func testMinAttemptsBoundary() {
        let steps: [Step] = secureSteps()
        let five: SkillState = feed(fresh(), Array(steps.prefix(5)))
        XCTAssertEqual(five.attempts, 5)
        XCTAssertEqual(five.sessionsSeen.count, 2)
        XCTAssertEqual(five.daysSeen.count, 2)
        XCTAssertFalse(Mastery.isSecure(five, settings: settings))
        XCTAssertEqual(five.status, .learning)
        let six: SkillState = feed(fresh(), Array(steps.prefix(6)))
        XCTAssertTrue(Mastery.isSecure(six, settings: settings))
        XCTAssertEqual(six.status, .secure)
    }

    func testMinSessionsBoundary() {
        var steps: [Step] = []
        for _ in 0..<3 { steps.append((true, "a", 0, .listenChooseSound)) }
        for _ in 0..<3 { steps.append((true, "a", 1, .findGrapheme)) }
        let below: SkillState = feed(fresh(), steps)
        XCTAssertEqual(below.sessionsSeen.count, 1)
        XCTAssertFalse(Mastery.isSecure(below, settings: settings))
        let above: SkillState = feed(below, [(true, "b", 1, .findGrapheme)])
        XCTAssertTrue(Mastery.isSecure(above, settings: settings))
    }

    func testMinDaysBoundary() {
        var steps: [Step] = []
        for _ in 0..<3 { steps.append((true, "a", 0, .listenChooseSound)) }
        for _ in 0..<3 { steps.append((true, "b", 0, .findGrapheme)) }
        let below: SkillState = feed(fresh(), steps)
        XCTAssertEqual(below.daysSeen.count, 1)
        XCTAssertFalse(Mastery.isSecure(below, settings: settings))
        let above: SkillState = feed(below, [(true, "b", 1, .findGrapheme)])
        XCTAssertTrue(Mastery.isSecure(above, settings: settings))
    }

    func testMinActivityTypesBoundary() {
        var steps: [Step] = []
        for _ in 0..<3 { steps.append((true, "a", 0, .listenChooseSound)) }
        for _ in 0..<3 { steps.append((true, "b", 1, .listenChooseSound)) }
        let below: SkillState = feed(fresh(), steps)
        XCTAssertEqual(below.activityTypesSeen.count, 1)
        XCTAssertFalse(Mastery.isSecure(below, settings: settings))
        let above: SkillState = feed(below, [(true, "b", 1, .findGrapheme)])
        XCTAssertTrue(Mastery.isSecure(above, settings: settings))
    }

    func testScoreAndRecentErrorBoundariesOnMeetsEvidence() {
        var base: SkillState = fresh()
        base.score = 0.9
        base.attempts = 6
        base.sessionsSeen = ["a", "b"]
        base.daysSeen = ["2023-11-14", "2023-11-15"]
        base.activityTypesSeen = [.listenChooseSound, .findGrapheme]
        base.recentResults = [true, true, true, true, true, true]
        XCTAssertTrue(Mastery.meetsEvidence(base, settings: settings))

        var s: SkillState = base
        s.score = settings.secureScore - 0.001
        XCTAssertFalse(Mastery.meetsEvidence(s, settings: settings))
        s.score = settings.secureScore
        XCTAssertTrue(Mastery.meetsEvidence(s, settings: settings))

        s = base
        s.attempts = settings.minAttempts - 1
        XCTAssertFalse(Mastery.meetsEvidence(s, settings: settings))

        s = base
        s.recentResults = [true, true, true, true, true, true, true, false]   // one error allowed
        XCTAssertTrue(Mastery.meetsEvidence(s, settings: settings))
        s.recentResults = [true, true, true, true, true, true, false, false]  // two errors: not allowed
        XCTAssertFalse(Mastery.meetsEvidence(s, settings: settings))
        // An error that has slid out of the 8-wide window no longer counts.
        s.recentResults = [false, false, true, true, true, true, true, true, true, true]
        XCTAssertTrue(Mastery.meetsEvidence(s, settings: settings))
    }

    func testStricterSettingsAreRespected() {
        var strict: MasterySettings = MasterySettings()
        strict.secureScore = 0.99
        let s: SkillState = secureSkill("g-s", .recognise, settings: strict)
        XCTAssertFalse(Mastery.isSecure(s, settings: strict))
        XCTAssertTrue(s.score < 0.99)
    }

    // MARK: Prompted / modelled

    func testPromptedAndModelledAttemptsNeverMakeASkillSecure() {
        var s: SkillState = fresh()
        for i in 0..<40 {
            let support: SupportLevel = i % 2 == 0 ? .prompted : .modelled
            let a: Attempt = makeAttempt(type: i % 3 == 0 ? .findGrapheme : .listenChooseSound, correct: true, support: support,
                                         session: "s\(i % 4)", at: day(i % 5))
            s = Mastery.update(skill: s, attempt: a, settings: settings, now: day(i % 5))
        }
        XCTAssertNotEqual(s.status, .secure)
        XCTAssertFalse(Mastery.isSecure(s, settings: settings))
        XCTAssertEqual(s.attempts, 0)
        XCTAssertEqual(s.independentCorrect, 0)
        XCTAssertEqual(s.score, 0)
        XCTAssertTrue(s.sessionsSeen.isEmpty)
        XCTAssertTrue(s.daysSeen.isEmpty)
        XCTAssertTrue(s.recentResults.isEmpty)
    }

    func testPromptedCorrectDoesNotHelpIndependentEvidence() {
        var steps: [Step] = Array(secureSteps().prefix(5))
        var s: SkillState = feed(fresh(), steps)
        for _ in 0..<10 {
            s = Mastery.update(skill: s, attempt: makeAttempt(correct: true, support: .prompted, session: "c"), settings: settings, now: day(1))
        }
        XCTAssertFalse(Mastery.isSecure(s, settings: settings), "five independent answers plus help is still five")
        steps = [(true, "b", 1, .findGrapheme)]
        XCTAssertTrue(Mastery.isSecure(feed(s, steps), settings: settings))
    }

    func testPromptedWrongBarelyMovesTheScore() {
        let secure: SkillState = secureSkill("g-s", .recognise)
        for support in [SupportLevel.prompted, SupportLevel.modelled] {
            let after: SkillState = Mastery.update(skill: secure, attempt: makeAttempt(correct: false, support: support), settings: settings, now: day(3))
            XCTAssertGreaterThanOrEqual(after.score, secure.score - Mastery.promptedPenalty - 1e-9)
            XCTAssertEqual(after.status, .secure)
            XCTAssertEqual(after.recentResults, secure.recentResults)
            XCTAssertEqual(after.attempts, secure.attempts)
            XCTAssertEqual(after.reviewStage, secure.reviewStage)
            XCTAssertEqual(after.struggleStreak, secure.struggleStreak)
        }
    }

    // MARK: One error never erases progress

    func testSingleIndependentErrorKeepsASecureSkillSecure() {
        var s: SkillState = secureSkill("g-s", .recognise)
        s.reviewStage = 3
        let after: SkillState = Mastery.update(skill: s, attempt: makeAttempt(correct: false, session: "c", at: day(3)), settings: settings, now: day(3))
        XCTAssertEqual(after.status, .secure)
        XCTAssertTrue(Mastery.isSecure(after, settings: settings))
        XCTAssertEqual(after.reviewStage, 2, "stage drops by one, not to zero")
        XCTAssertEqual(after.nextReviewAt, day(3).addingTimeInterval(Scheduler.secondsPerDay), "sooner look after an error")
        XCTAssertEqual(after.independentCorrect, s.independentCorrect, "earlier successes are kept")
        XCTAssertNotNil(after.secureAt)
    }

    func testRepeatedErrorsDemoteToReviewDueAndRecoveryRestores() {
        var s: SkillState = secureSkill("g-s", .recognise)
        s.reviewStage = 3
        s = Mastery.update(skill: s, attempt: makeAttempt(correct: false, at: day(3)), settings: settings, now: day(3))
        XCTAssertEqual(s.status, .secure)
        s = Mastery.update(skill: s, attempt: makeAttempt(correct: false, at: day(3)), settings: settings, now: day(3))
        XCTAssertEqual(s.status, .reviewDue)
        XCTAssertEqual(s.reviewStage, 0)
        XCTAssertFalse(Mastery.isSecure(s, settings: settings))
        XCTAssertTrue(Mastery.isEstablished(s, settings: settings), "a refresher must not re-lock later units")
        for i in 0..<6 {
            s = Mastery.update(skill: s, attempt: makeAttempt(correct: true, session: "d", at: day(4 + i)), settings: settings, now: day(4 + i))
        }
        XCTAssertEqual(s.status, .secure)
    }

    func testOneErrorWhileLearningKeepsCountsAndScore() {
        var steps: [Step] = Array(secureSteps().prefix(5))
        steps.append((false, "b", 1, .findGrapheme))
        let s: SkillState = feed(fresh(), steps)
        XCTAssertEqual(s.independentCorrect, 5)
        XCTAssertEqual(s.attempts, 6)
        XCTAssertGreaterThan(s.score, 0.5)
        XCTAssertEqual(s.status, .learning)
        // Two more right answers and the single error no longer blocks mastery.
        let later: SkillState = feed(s, [(true, "b", 1, .findGrapheme), (true, "b", 1, .listenChooseSound), (true, "b", 1, .findGrapheme)])
        XCTAssertTrue(Mastery.isSecure(later, settings: settings))
    }

    // MARK: Response time

    func testSlowAnswersAreNeverPenalised() {
        func run(_ ms: Int?) -> SkillState {
            var s: SkillState = fresh()
            for (i, st) in secureSteps().enumerated() {
                let a: Attempt = makeAttempt(type: st.type, correct: st.correct, session: st.session, ms: ms, at: day(st.day))
                s = Mastery.update(skill: s, attempt: a, settings: settings, now: day(st.day))
                _ = i
            }
            return s
        }
        let slow: SkillState = run(60_000)
        let none: SkillState = run(nil)
        XCTAssertEqual(slow, none)
        XCTAssertTrue(Mastery.isSecure(slow, settings: settings))
    }

    func testSpeedAloneNeverMakesASkillSecure() {
        var s: SkillState = fresh()
        for _ in 0..<12 {
            s = Mastery.update(skill: s, attempt: makeAttempt(correct: true, session: "only", ms: 400, at: day(0)), settings: settings, now: day(0))
        }
        XCTAssertFalse(Mastery.isSecure(s, settings: settings), "one session, one day, one activity type")
        XCTAssertEqual(s.status, .learning)
    }

    func testSpeedIsOnlyANarrowTiebreaker() {
        var near: SkillState = fresh()
        near.attempts = 6
        near.independentCorrect = 6
        near.score = 0.77
        near.sessionsSeen = ["a", "b"]
        near.daysSeen = ["2023-11-14", "2023-11-15"]
        near.activityTypesSeen = [.listenChooseSound, .findGrapheme]
        near.recentResults = [true, true, true, true, true, true]
        near.status = .learning

        func next(_ s: SkillState, ms: Int?, _ st: MasterySettings) -> SkillState {
            return Mastery.update(skill: s, attempt: makeAttempt(correct: true, session: "b", ms: ms, at: day(1)), settings: st, now: day(1))
        }
        XCTAssertFalse(Mastery.isSecure(next(near, ms: nil, settings), settings: settings))
        XCTAssertFalse(Mastery.isSecure(next(near, ms: 60_000, settings), settings: settings), "slow is never worse, never better")
        XCTAssertTrue(Mastery.isSecure(next(near, ms: 900, settings), settings: settings), "a fast answer breaks a near-tie")
        var noTime: MasterySettings = settings
        noTime.useResponseTime = false
        XCTAssertFalse(Mastery.isSecure(next(near, ms: 900, noTime), settings: noTime))
        // Not near enough: speed cannot rescue a clearly insufficient score.
        var far: SkillState = near
        far.score = 0.5
        XCTAssertFalse(Mastery.isSecure(next(far, ms: 900, settings), settings: settings))
        // Missing another rule: speed cannot rescue it.
        var oneSession: SkillState = near
        oneSession.sessionsSeen = ["b"]
        XCTAssertFalse(Mastery.isSecure(next(oneSession, ms: 900, settings), settings: settings))
        // Recent error: speed cannot rescue it.
        var erred: SkillState = near
        erred.recentResults = [true, true, true, true, true, false]
        XCTAssertFalse(Mastery.isSecure(next(erred, ms: 900, settings), settings: settings))
    }

    // MARK: Bookkeeping

    func testStruggleStreak() {
        var s: SkillState = fresh()
        for _ in 0..<3 { s = Mastery.update(skill: s, attempt: makeAttempt(correct: false), settings: settings, now: day(0)) }
        XCTAssertEqual(s.struggleStreak, 3)
        s = Mastery.update(skill: s, attempt: makeAttempt(correct: false, support: .modelled), settings: settings, now: day(0))
        XCTAssertEqual(s.struggleStreak, 3, "help-assisted attempts neither add to nor clear the streak")
        s = Mastery.update(skill: s, attempt: makeAttempt(correct: true), settings: settings, now: day(0))
        XCTAssertEqual(s.struggleStreak, 0)
    }

    func testRecentWindowIsCappedAndSessionsAreUnique() {
        var s: SkillState = fresh()
        for i in 0..<20 {
            s = Mastery.update(skill: s, attempt: makeAttempt(correct: i % 5 != 0, session: "same"), settings: settings, now: day(0))
        }
        XCTAssertEqual(s.recentResults.count, 8)
        XCTAssertEqual(s.sessionsSeen, ["same"])
        XCTAssertEqual(s.daysSeen.count, 1)
        XCTAssertEqual(s.attempts, 20)
    }

    func testDayKeyIsUTCCalendarDay() {
        XCTAssertEqual(DayKey.string(for: Date(timeIntervalSince1970: 0)), "1970-01-01")
        XCTAssertEqual(DayKey.string(for: Date(timeIntervalSince1970: 86_399)), "1970-01-01")
        XCTAssertEqual(DayKey.string(for: Date(timeIntervalSince1970: 86_400)), "1970-01-02")
    }

    func testUnitMasteryNeedsAllApplicableTracks() {
        let recognise: SkillState = secureSkill("g-s", .recognise)
        let read: SkillState = secureSkill("g-s", .read)
        XCTAssertFalse(Mastery.isUnitMastered(unitId: "g-s", tracks: [.recognise, .read], skills: [recognise], settings: settings))
        XCTAssertTrue(Mastery.isUnitMastered(unitId: "g-s", tracks: [.recognise, .read], skills: [recognise, read], settings: settings))
        XCTAssertFalse(Mastery.isUnitMastered(unitId: "g-s", tracks: [], skills: [recognise, read], settings: settings))
    }
}
