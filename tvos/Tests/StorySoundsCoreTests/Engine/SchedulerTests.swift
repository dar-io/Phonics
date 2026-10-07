import XCTest
@testable import StorySoundsCore

final class SchedulerTests: XCTestCase {
    private let settings: MasterySettings = MasterySettings()

    func testIntervalLadderClampsAndHasAFallback() {
        XCTAssertEqual(Scheduler.intervalDays(forStage: 0, settings: settings), 1)
        XCTAssertEqual(Scheduler.intervalDays(forStage: 2, settings: settings), 7)
        XCTAssertEqual(Scheduler.intervalDays(forStage: 99, settings: settings), 60)
        XCTAssertEqual(Scheduler.intervalDays(forStage: -4, settings: settings), 1)
        var empty: MasterySettings = MasterySettings()
        empty.reviewLadderDays = []
        XCTAssertEqual(Scheduler.intervalDays(forStage: 3, settings: empty), 1)
    }

    func testFirstReviewIsScheduledWhenSkillBecomesSecure() {
        let s: SkillState = secureSkill("g-s", .recognise)
        XCTAssertEqual(s.status, .secure)
        // Became secure on day 1 (6th answer); stage 0 = one day.
        XCTAssertEqual(s.nextReviewAt, day(2))
        XCTAssertEqual(s.reviewStage, 0)
        XCTAssertFalse(Scheduler.isDue(s, now: day(1)))
        XCTAssertTrue(Scheduler.isDue(s, now: day(2)))
    }

    func testCorrectAnswerOnADueReviewAdvancesTheStage() {
        let s: SkillState = secureSkill("g-s", .recognise)
        let after: SkillState = Mastery.update(skill: s, attempt: makeAttempt(correct: true, session: "r", at: day(2)), settings: settings, now: day(2))
        XCTAssertEqual(after.status, .secure)
        XCTAssertEqual(after.reviewStage, 1)
        XCTAssertEqual(after.nextReviewAt, day(2).addingTimeInterval(3 * Scheduler.secondsPerDay))
        let again: SkillState = Mastery.update(skill: after, attempt: makeAttempt(correct: true, session: "r", at: day(5)), settings: settings, now: day(5))
        XCTAssertEqual(again.reviewStage, 2)
        XCTAssertEqual(again.nextReviewAt, day(5).addingTimeInterval(7 * Scheduler.secondsPerDay))
    }

    func testCorrectAnswerThatIsNotAReviewDoesNotAdvanceTheStage() {
        let s: SkillState = secureSkill("g-s", .recognise)
        let after: SkillState = Mastery.update(skill: s, attempt: makeAttempt(correct: true, session: "x", at: day(1)), settings: settings, now: day(1))
        XCTAssertEqual(after.reviewStage, s.reviewStage)
        XCTAssertEqual(after.nextReviewAt, s.nextReviewAt)
    }

    func testStageStopsAtTheEndOfTheLadder() {
        var s: SkillState = secureSkill("g-s", .recognise)
        s.reviewStage = settings.reviewLadderDays.count - 1
        s.nextReviewAt = day(10)
        let after: SkillState = Mastery.update(skill: s, attempt: makeAttempt(correct: true, at: day(11)), settings: settings, now: day(11))
        XCTAssertEqual(after.reviewStage, settings.reviewLadderDays.count - 1)
        XCTAssertEqual(after.nextReviewAt, day(11).addingTimeInterval(60 * Scheduler.secondsPerDay))
    }

    func testErrorBringsTheNextReviewSoonerThanSuccess() {
        var s: SkillState = secureSkill("g-s", .recognise)
        s.reviewStage = 4
        s.nextReviewAt = day(10)
        let ok: SkillState = Mastery.update(skill: s, attempt: makeAttempt(correct: true, at: day(10)), settings: settings, now: day(10))
        let bad: SkillState = Mastery.update(skill: s, attempt: makeAttempt(correct: false, at: day(10)), settings: settings, now: day(10))
        XCTAssertEqual(ok.reviewStage, 5)
        XCTAssertEqual(bad.reviewStage, 3)
        XCTAssertEqual(bad.nextReviewAt, day(10).addingTimeInterval(Scheduler.secondsPerDay))
        XCTAssertGreaterThan(ok.nextReviewAt ?? day(0), bad.nextReviewAt ?? day(99))
    }

    func testDueSkillsAreSortedByOverdueness() {
        func skill(_ unit: String, _ status: SkillStatus, next: Date?, last: Date? = nil) -> SkillState {
            var s: SkillState = SkillState(unitId: unit, track: .recognise)
            s.status = status
            s.nextReviewAt = next
            s.lastAttemptAt = last
            return s
        }
        var snap: LearnerSnapshot = makeSnapshot()
        snap.skills = [
            skill("a", .secure, next: day(2)),               // 3 days overdue at day 5
            skill("b", .secure, next: day(1)),               // 4 days overdue
            skill("c", .secure, next: day(10)),              // not due yet
            skill("d", .new, next: nil),                     // never due
            skill("e", .reviewDue, next: nil, last: day(0)), // demoted: 5 days
            skill("f", .secure, next: day(2)),               // ties with a: unit id order
        ]
        let due: [SkillState] = Scheduler.dueSkills(snapshot: snap, now: day(5))
        XCTAssertEqual(due.map { $0.unitId }, ["e", "b", "a", "f"])
    }

    func testNewSkillsAreNeverDue() {
        XCTAssertFalse(Scheduler.isDue(SkillState(unitId: "x", track: .read), now: day(100)))
    }
}
