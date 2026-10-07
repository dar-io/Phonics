import XCTest
@testable import StorySoundsCore

final class HoldGateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testProgressRisesAndCompletes() {
        var g = HoldGate(requiredDuration: 3)
        XCTAssertEqual(g.progress(at: t0), 0)
        g.begin(at: t0)
        XCTAssertEqual(g.progress(at: t0.addingTimeInterval(1.5)), 0.5, accuracy: 0.0001)
        XCTAssertFalse(g.update(at: t0.addingTimeInterval(2.9)))
        XCTAssertTrue(g.update(at: t0.addingTimeInterval(3)))
        XCTAssertEqual(g.progress(at: t0.addingTimeInterval(100)), 1)
        XCTAssertTrue(g.isSatisfied)
    }

    func testCancelResetsProgress() {
        var g = HoldGate(requiredDuration: 3)
        g.begin(at: t0)
        g.cancel()
        XCTAssertEqual(g.progress(at: t0.addingTimeInterval(2)), 0)
        g.begin(at: t0.addingTimeInterval(2))
        XCTAssertFalse(g.update(at: t0.addingTimeInterval(4)))
        XCTAssertTrue(g.update(at: t0.addingTimeInterval(5)))
    }

    func testRepeatedBeginDoesNotRestartAndClockSkewIsClamped() {
        var g = HoldGate(requiredDuration: 2)
        g.begin(at: t0); g.begin(at: t0.addingTimeInterval(1))
        XCTAssertTrue(g.update(at: t0.addingTimeInterval(2)))
        var h = HoldGate(requiredDuration: 2)
        h.begin(at: t0)
        XCTAssertEqual(h.progress(at: t0.addingTimeInterval(-5)), 0)
    }
}

final class AdultChallengeTests: XCTestCase {
    func testDeterministicForSeed() {
        XCTAssertEqual(AdultChallengeFactory.make(seed: 42), AdultChallengeFactory.make(seed: 42))
        let differing = (1...20).map { AdultChallengeFactory.make(seed: UInt64($0)).prompt }
        XCTAssertGreaterThan(Set(differing).count, 10)
    }

    func testOptionsAreSaneForManySeeds() {
        var kinds = Set<AdultChallengeKind>()
        for seed in 0..<500 {
            let c = AdultChallengeFactory.make(seed: UInt64(seed))
            kinds.insert(c.kind)
            XCTAssertEqual(c.options.count, 4, "seed \(seed)")
            XCTAssertEqual(Set(c.options).count, 4, "options must be distinct, seed \(seed)")
            XCTAssertTrue((0..<4).contains(c.correctIndex))
            XCTAssertTrue(c.isCorrect(optionIndex: c.correctIndex))
            XCTAssertTrue(c.options.allSatisfy { Int($0).map { $0 > 0 } ?? false })
        }
        XCTAssertEqual(kinds, [.arithmetic, .numberWords])
    }

    func testCorrectAnswerMatchesPrompt() {
        for seed in 0..<200 {
            let c = AdultChallengeFactory.make(seed: UInt64(seed))
            guard c.kind == .arithmetic else { continue }
            // "What is A × B − C?"
            let nums = c.prompt.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
            XCTAssertEqual(nums.count, 3)
            XCTAssertEqual(c.options[c.correctIndex], String(nums[0] * nums[1] - nums[2]))
        }
    }

    func testNumberWords() {
        XCTAssertEqual(AdultChallengeFactory.numberWords(0), "zero")
        XCTAssertEqual(AdultChallengeFactory.numberWords(13), "thirteen")
        XCTAssertEqual(AdultChallengeFactory.numberWords(40), "forty")
        XCTAssertEqual(AdultChallengeFactory.numberWords(47), "forty-seven")
        XCTAssertEqual(AdultChallengeFactory.numberWords(105), "one hundred and five")
    }

    func testNumberWordsPromptDoesNotUseDigits() {
        for seed in 0..<100 {
            let c = AdultChallengeFactory.make(seed: UInt64(seed))
            if c.kind == .numberWords { XCTAssertNil(c.prompt.rangeOfCharacter(from: .decimalDigits)) }
        }
    }
}

final class GateLockoutTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 5_000)

    func testLocksAfterThreeFailuresWithBackoff() {
        var l = GateLockout()
        XCTAssertNil(l.recordFailure(at: t0)); XCTAssertNil(l.recordFailure(at: t0))
        XCTAssertEqual(l.recordFailure(at: t0), 30)
        XCTAssertTrue(l.isLocked(at: t0.addingTimeInterval(29)))
        XCTAssertEqual(l.remaining(at: t0.addingTimeInterval(10)), 20, accuracy: 0.001)
        XCTAssertFalse(l.isLocked(at: t0.addingTimeInterval(31)))
        let t1 = t0.addingTimeInterval(31)
        l.recordFailure(at: t1); l.recordFailure(at: t1)
        XCTAssertEqual(l.recordFailure(at: t1), 60)
    }

    func testBackoffIsCapped() {
        var l = GateLockout(); var t = t0; var last: TimeInterval = 0
        for _ in 0..<12 {
            l.recordFailure(at: t); l.recordFailure(at: t)
            last = l.recordFailure(at: t) ?? 0
            t = t.addingTimeInterval(last + 1)
        }
        XCTAssertEqual(last, GateLockout.maxSeconds)
    }

    func testSuccessResetsAndCodableRoundTrip() throws {
        var l = GateLockout()
        l.recordFailure(at: t0); l.recordFailure(at: t0); l.recordFailure(at: t0)
        let data = try JSONEncoder().encode(l)
        let back = try JSONDecoder().decode(GateLockout.self, from: data)
        XCTAssertEqual(back, l)
        l.recordSuccess()
        XCTAssertFalse(l.isLocked(at: t0)); XCTAssertEqual(l.failures, 0)
    }

    func testFailureWhileLockedDoesNotExtend() {
        var l = GateLockout()
        for _ in 0..<3 { l.recordFailure(at: t0) }
        let until = l.lockedUntil
        _ = l.recordFailure(at: t0.addingTimeInterval(5))
        XCTAssertEqual(l.lockedUntil, until)
    }
}

final class ParentGateSessionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 9_000)

    private func reachChallenge(_ s: inout ParentGateSession, at t: Date, seed: UInt64 = 7) -> AdultChallenge? {
        s.holdBegan(at: t)
        s.holdTick(at: t.addingTimeInterval(10), challengeSeed: seed)
        if case let .challenge(c) = s.stage { return c }
        return nil
    }

    func testHappyPath() throws {
        var s = ParentGateSession(requiredHold: 3)
        s.holdBegan(at: t0)
        s.holdTick(at: t0.addingTimeInterval(1), challengeSeed: 1)
        XCTAssertEqual(s.stage, .hold)
        s.holdTick(at: t0.addingTimeInterval(3), challengeSeed: 1)
        guard case let .challenge(c) = s.stage else { return XCTFail("expected challenge") }
        s.answer(optionIndex: c.correctIndex, at: t0, nextSeed: 2)
        XCTAssertEqual(s.stage, .unlocked)
        s.relock()
        XCTAssertEqual(s.stage, .hold)
    }

    func testReleasingEarlyCancels() {
        var s = ParentGateSession(requiredHold: 3)
        s.holdBegan(at: t0); s.holdCancelled()
        s.holdTick(at: t0.addingTimeInterval(10), challengeSeed: 1)
        XCTAssertEqual(s.stage, .hold)
    }

    private func failThrice(_ s: inout ParentGateSession, at t: Date) -> Bool {
        for i in 0..<3 {
            guard case let .challenge(cur) = s.stage else { return false }
            s.answer(optionIndex: (cur.correctIndex + 1) % 4, at: t, nextSeed: UInt64(100 + i))
        }
        return true
    }

    func testThreeWrongAnswersLockOutThenRecovers() throws {
        var s = ParentGateSession(requiredHold: 1)
        XCTAssertNotNil(reachChallenge(&s, at: t0))
        XCTAssertTrue(failThrice(&s, at: t0))
        guard case let .lockedOut(until) = s.stage else { return XCTFail("expected lockout, got \(s.stage)") }
        XCTAssertEqual(until, t0.addingTimeInterval(30))
        s.holdBegan(at: t0.addingTimeInterval(5))
        s.holdTick(at: t0.addingTimeInterval(20), challengeSeed: 5)
        XCTAssertEqual(s.stage, .lockedOut(until: until))
        s.refresh(at: until.addingTimeInterval(1))
        XCTAssertEqual(s.stage, .hold)
    }

    func testLockoutPersistsAcrossSessionsViaCodableState() throws {
        var s = ParentGateSession(requiredHold: 1)
        XCTAssertNotNil(reachChallenge(&s, at: t0))
        XCTAssertTrue(failThrice(&s, at: t0))
        var fresh = ParentGateSession(requiredHold: 1, lockout: s.lockout)
        fresh.refresh(at: t0.addingTimeInterval(1))
        if case .lockedOut = fresh.stage {} else { XCTFail("lockout should survive") }
    }
}

final class ParentReportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_100_000)

    private func curriculum() throws -> Curriculum { try PSFixtures.curriculum(unitIds: ["u1", "u2", "u3", "u4"]) }

    private func skill(_ unit: String, _ status: SkillStatus, nextReview: Date? = nil) -> SkillState {
        var k = PSFixtures.skill(unit, .recognise, status: status, attempts: 5)
        k.nextReviewAt = nextReview
        return k
    }

    func testDerivesStatusesFromSkillEvidence() throws {
        let snap = PSFixtures.snapshot(skills: [
            skill("u1", .secure, nextReview: now.addingTimeInterval(86_400)),
            skill("u2", .secure, nextReview: now.addingTimeInterval(-60)),
            skill("u3", .learning),
        ])
        let r = ParentReport.make(curriculum: try curriculum(), snapshot: snap, now: now)
        XCTAssertEqual(r.masteredUnitIds, ["u1"])
        XCTAssertEqual(r.dueForReviewUnitIds, ["u2"])
        XCTAssertEqual(r.developingUnitIds, ["u3"])
        XCTAssertEqual(r.currentPosition?.id, "u3")
        XCTAssertEqual(r.mastered.first?.label, "u1 (/u1/)")
    }

    func testMixedTracksNotAllSecureIsDeveloping() throws {
        let snap = PSFixtures.snapshot(skills: [
            PSFixtures.skill("u1", .recognise, status: .secure), PSFixtures.skill("u1", .blend, status: .learning),
        ])
        let r = ParentReport.make(curriculum: try curriculum(), snapshot: snap, now: now)
        XCTAssertEqual(r.developingUnitIds, ["u1"])
        XCTAssertTrue(r.masteredUnitIds.isEmpty)
    }

    func testInputsOverrideDerivationAndSetCurrentUnit() throws {
        let inputs = ReportInputs(unitStatuses: ["u1": .mastered, "u2": .mastered, "u3": .reviewDue, "u4": .inProgress], currentUnitId: "u4")
        let r = ParentReport.make(curriculum: try curriculum(), snapshot: PSFixtures.snapshot(), now: now, inputs: inputs)
        XCTAssertEqual(r.mastered.map { $0.id }, ["u1", "u2"])
        XCTAssertEqual(r.dueForReview.map { $0.id }, ["u3"])
        XCTAssertEqual(r.currentPosition?.id, "u4")
    }

    func testFreshLearnerStartsAtFirstUnitWithStarterSuggestion() throws {
        let r = ParentReport.make(curriculum: try curriculum(), snapshot: PSFixtures.snapshot(), now: now)
        XCTAssertEqual(r.currentPosition?.id, "u1")
        XCTAssertTrue(r.mastered.isEmpty)
        XCTAssertTrue(r.suggestedPractice.contains("Five-minute"))
    }

    func testRecentSessionsNewestFirstCappedAtFive() throws {
        let r = ParentReport.make(curriculum: try curriculum(), snapshot: PSFixtures.snapshot(sessions: 8), now: now)
        XCTAssertEqual(r.recentSessions.count, 5)
        XCTAssertEqual(r.recentSessions.first?.id, "sess-7")
        XCTAssertEqual(r.recentSessions.first?.accuracyPercent, 80)
        XCTAssertEqual(r.totalSessions, 8)
    }

    func testTopConfusionsSortedAndCapped() throws {
        let r = ParentReport.make(curriculum: try curriculum(), snapshot: PSFixtures.snapshot(confusions: 9), now: now)
        XCTAssertEqual(r.topConfusions.count, 5)
        XCTAssertEqual(r.topConfusions.first?.count, 9)
        XCTAssertEqual(r.topConfusions.map { $0.count }, [9, 8, 7, 6, 5])
    }

    func testSuggestionMentionsReviewCurrentAndConfusion() throws {
        var snap = PSFixtures.snapshot(skills: [skill("u1", .reviewDue), skill("u2", .learning)])
        snap.confusions = [ConfusionRecord(expected: "b", chosen: "d", count: 4, lastAt: now)]
        let r = ParentReport.make(curriculum: try curriculum(), snapshot: snap, now: now)
        XCTAssertEqual(r.suggestedPracticeSteps.count, 4)
        XCTAssertTrue(r.suggestedPractice.contains("u1 (/u1/)"))
        XCTAssertTrue(r.suggestedPractice.contains("u2 (/u2/)"))
        XCTAssertTrue(r.suggestedPractice.contains("'b'") && r.suggestedPractice.contains("'d'"))
    }

    func testHumanReadableSummaryContainsKeyFactsAndNoApprovalClaim() throws {
        var snap = PSFixtures.snapshot(sessions: 2, skills: [skill("u1", .secure, nextReview: now.addingTimeInterval(1000))])
        snap.profile.stickers = ["star", "moon"]
        let text = ParentReport.make(curriculum: try curriculum(), snapshot: snap, now: now)
            .humanReadableSummary(timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertTrue(text.contains("Robin"))
        XCTAssertTrue(text.contains("Secure: 1"))
        XCTAssertTrue(text.contains("Stickers: 2"))
        XCTAssertTrue(text.contains("not approved or endorsed"))
        XCTAssertFalse(text.lowercased().contains("approved by little wandle"))
    }
}
