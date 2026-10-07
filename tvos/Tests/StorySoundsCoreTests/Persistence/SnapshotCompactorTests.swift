import XCTest
@testable import StorySoundsCore

final class SnapshotCompactorTests: XCTestCase {
    func testSmallSnapshotUnchanged() {
        let s = PSFixtures.snapshot(attempts: 10, sessions: 3, confusions: 2)
        let r = SnapshotCompactor().compact(s)
        XCTAssertEqual(r.snapshot.attempts.count, 10)
        XCTAssertEqual(r.snapshot.sessions.count, 3)
        XCTAssertEqual(r.attemptsDropped, 0)
        XCTAssertTrue(r.fitsBudget)
    }

    func testKeepsMostRecentAttempts() {
        var c = SnapshotCompactor(); c.maxAttempts = 20
        let r = c.compact(PSFixtures.snapshot(attempts: 100))
        XCTAssertEqual(r.snapshot.attempts.count, 20)
        XCTAssertEqual(r.snapshot.attempts.first?.itemKey, "item-80")
        XCTAssertEqual(r.snapshot.attempts.last?.itemKey, "item-99")
        XCTAssertEqual(r.attemptsDropped, 80)
    }

    func testDropsOldestSessionsBeyondCap() {
        var c = SnapshotCompactor(); c.maxSessions = 5
        let r = c.compact(PSFixtures.snapshot(sessions: 12))
        XCTAssertEqual(r.snapshot.sessions.map { $0.id }, (7..<12).map { "sess-\($0)" })
        XCTAssertEqual(r.sessionsDropped, 7)
    }

    func testDroppedWrongAnswersFoldIntoMissingConfusionOnly() {
        var s = PSFixtures.snapshot(attempts: 0)
        s.attempts = [PSFixtures.attempt(0, correct: false), PSFixtures.attempt(1, correct: true), PSFixtures.attempt(2, correct: true)]
        var c = SnapshotCompactor(); c.maxAttempts = 2
        var r = c.compact(s)
        XCTAssertEqual(r.snapshot.confusions.count, 1)
        XCTAssertEqual(r.snapshot.confusions.first?.expected, "s")
        // Existing record is not double counted.
        s.confusions = [ConfusionRecord(expected: "s", chosen: "z", count: 7, lastAt: PSFixtures.t0)]
        r = c.compact(s)
        XCTAssertEqual(r.snapshot.confusions.first?.count, 7)
    }

    func testBudgetIsGuaranteedForHugeSnapshot() {
        var s = PSFixtures.snapshot(attempts: 6000, sessions: 800, confusions: 600)
        s.skills = (0..<60).map { i in
            var k = PSFixtures.skill("u\(i)")
            k.sessionsSeen = (0..<300).map { "session-\($0)" }
            k.daysSeen = (0..<300).map { "2025-01-\($0)" }
            return k
        }
        XCTAssertGreaterThan(SnapshotCompactor.encodedSize(of: s), SnapshotCompactor.defaultBudget)
        let r = SnapshotCompactor().compact(s)
        XCTAssertTrue(r.fitsBudget)
        XCTAssertLessThanOrEqual(r.encodedBytes, SnapshotCompactor.defaultBudget)
        XCTAssertEqual(r.snapshot.skills.count, 60, "skill states must never be dropped")
        XCTAssertEqual(r.snapshot.profile, s.profile)
    }

    func testTightBudgetShrinksFurtherAndTerminates() {
        let s = PSFixtures.snapshot(attempts: 300, sessions: 50, confusions: 50)
        let c = SnapshotCompactor(byteBudget: 3_000)
        let r = c.compact(s)
        XCTAssertLessThanOrEqual(r.encodedBytes, 3_000)
        XCTAssertTrue(r.fitsBudget)
    }

    func testImpossibleBudgetReportsNotFitting() {
        let r = SnapshotCompactor(byteBudget: 10).compact(PSFixtures.snapshot(attempts: 5))
        XCTAssertFalse(r.fitsBudget)
    }
}
