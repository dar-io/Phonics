import XCTest
@testable import StorySoundsCore

final class SessionPlannerTests: XCTestCase {
    private var fx: RealData { return TestData.fixture }
    private var real: RealData { return TestData.real }

    private func plan(_ data: RealData, _ snap: LearnerSnapshot, now: Date = day(0), seed: UInt64 = 1, minutes: Int? = 7, focus: String? = nil) -> SessionPlan {
        return SessionPlanner.plan(index: data.index, snapshot: snap, now: now, seed: seed, minutes: minutes, focusUnitId: focus)
    }

    private func assertWellFormed(_ p: SessionPlan, _ data: RealData, maxCount: Int) {
        XCTAssertFalse(p.activities.isEmpty, "a session must always have something to do")
        XCTAssertLessThanOrEqual(p.activities.count, maxCount)
        var counts: [String: Int] = [:]
        for a in p.activities {
            counts[a.key, default: 0] += 1
            let spec: ActivitySpec = ActivitySpec(unitId: a.unitId, type: a.type, knownOrder: p.knownOrder)
            validateActivity(a, spec: spec, index: data.index)
            XCTAssertLessThanOrEqual(data.index.unitOrder(id: a.unitId) ?? 999, p.knownOrder)
        }
        for (key, n) in counts { XCTAssertLessThanOrEqual(n, SessionPlanner.maxRepeatsPerItem, "\(key) repeated \(n) times") }
        for k in p.modelledKeys { XCTAssertTrue(p.activities.contains { $0.key == k }, "modelled key \(k) not in plan") }
        XCTAssertFalse(p.reasons.isEmpty)
    }

    // MARK: Shape

    func testFreshLearnerPlanIsSmallWellFormedAndCapsRepeats() {
        let p: SessionPlan = plan(fx, makeSnapshot())
        XCTAssertEqual(p.focusUnitId, "g-s")
        XCTAssertEqual(p.knownOrder, 1)
        assertWellFormed(p, fx, maxCount: 16)
        XCTAssertGreaterThanOrEqual(p.activities.count, 8)
    }

    func testRealFreshLearnerPlan() {
        let p: SessionPlan = plan(real, makeSnapshot())
        XCTAssertEqual(p.focusUnitId, "g-s")
        assertWellFormed(p, real, maxCount: 16)
        XCTAssertGreaterThanOrEqual(p.activities.count, 8)
    }

    func testSessionLengthFollowsMinutes() {
        let short: SessionPlan = plan(real, snapshotWithSecure(index: real.index, upTo: 20), now: day(30), minutes: 3)
        let long: SessionPlan = plan(real, snapshotWithSecure(index: real.index, upTo: 20), now: day(30), minutes: 10)
        XCTAssertLessThan(short.activities.count, long.activities.count)
        XCTAssertLessThanOrEqual(short.activities.count, 3 * 60 / SessionPlanner.secondsPerActivity + 1)
        XCTAssertLessThanOrEqual(long.activities.count, 10 * 60 / SessionPlanner.secondsPerActivity)
    }

    func testMidCurriculumMixOfFocusReviewAndMixedAndGentleEnding() {
        let snap: LearnerSnapshot = snapshotWithSecure(index: real.index, upTo: 30)
        let p: SessionPlan = plan(real, snap, now: day(40), seed: 5)
        XCTAssertEqual(p.focusUnitId, real.index.units.first(where: { $0.order == 31 })?.id)
        XCTAssertEqual(p.knownOrder, 31)
        assertWellFormed(p, real, maxCount: 16)
        XCTAssertGreaterThanOrEqual(p.activities.count, 12)

        let focusId: String = p.focusUnitId ?? ""
        let focusCount: Int = p.activities.filter { $0.unitId == focusId }.count
        let mixedCount: Int = p.activities.filter { $0.type == .mixedReview }.count
        let reviewCount: Int = p.activities.filter { $0.unitId != focusId && $0.type != .mixedReview }.count
        XCTAssertGreaterThanOrEqual(focusCount, 4)
        XCTAssertGreaterThanOrEqual(reviewCount, 3, "due reviews should be present")
        XCTAssertGreaterThanOrEqual(mixedCount, 1)
        let share: Double = Double(focusCount) / Double(p.activities.count)
        XCTAssertTrue(share > 0.2 && share < 0.65, "focus share \(share)")
        XCTAssertTrue([ActivityType.readStory, ActivityType.fluency].contains(p.activities.last?.type ?? .listenChooseSound), "ends gently")
        XCTAssertTrue(p.modelledKeys.isEmpty)
    }

    func testPlanIsDeterministicForEqualInputs() {
        let snap: LearnerSnapshot = snapshotWithSecure(index: real.index, upTo: 12)
        let a: SessionPlan = plan(real, snap, now: day(20), seed: 9)
        let b: SessionPlan = plan(real, snap, now: day(20), seed: 9)
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(a.activities, b.activities)
        XCTAssertEqual(a.reasons, b.reasons)
        var differs: Bool = false
        for s in 10..<16 where plan(real, snap, now: day(20), seed: UInt64(s)).activities != a.activities { differs = true }
        XCTAssertTrue(differs, "different seeds should vary the session")
    }

    func testEverySessionAcrossTheSequenceIsValid() {
        for upTo in stride(from: 0, to: real.index.maxOrder, by: 11) {
            let snap: LearnerSnapshot = snapshotWithSecure(index: real.index, upTo: upTo)
            for seed in 0..<2 {
                let p: SessionPlan = plan(real, snap, now: day(60), seed: UInt64(seed))
                assertWellFormed(p, real, maxCount: 16)
            }
        }
    }

    func testFullyMasteredLearnerStillGetsAReviewSession() {
        let snap: LearnerSnapshot = snapshotWithSecure(index: real.index, upTo: real.index.maxOrder)
        let p: SessionPlan = plan(real, snap, now: day(90))
        XCTAssertNil(p.focusUnitId)
        assertWellFormed(p, real, maxCount: 16)
    }

    func testConsolidationUnitAsFocusStillGetsAValidPlan() {
        // Everything before the first consolidation unit is secure, so it is the next unit. Derived from the data so a
        // content change that renumbers units (e.g. splitting a unit) cannot silently break this test.
        guard let cvcc = real.index.unit(id: "p4-cvcc") else { return XCTFail("p4-cvcc missing from the curriculum") }
        let snap: LearnerSnapshot = snapshotWithSecure(index: real.index, upTo: cvcc.order - 1)
        let p: SessionPlan = plan(real, snap, now: day(60), seed: 4)
        XCTAssertEqual(p.focusUnitId, "p4-cvcc")
        assertWellFormed(p, real, maxCount: 16)
        XCTAssertTrue(p.activities.contains { $0.unitId == "p4-cvcc" })
    }

    func testGrownUpCanChooseTheFocusUnit() {
        let p: SessionPlan = plan(real, makeSnapshot(), focus: "g-t")
        XCTAssertEqual(p.focusUnitId, "g-t")
        XCTAssertEqual(p.knownOrder, 3)
        assertWellFormed(p, real, maxCount: 16)
    }

    func testRevisitOverrideBringsTheUnitIntoReview() {
        var snap: LearnerSnapshot = snapshotWithSecure(index: real.index, upTo: 10, allTracks: true)
        snap.profile.overrides = [ParentOverride(unitId: "g-t", mode: .revisit, at: day(1))]
        let skillsBefore: [SkillState] = snap.skills
        let p: SessionPlan = plan(real, snap, now: day(1))
        XCTAssertEqual(snap.skills, skillsBefore, "an override never edits mastery evidence")
        XCTAssertTrue(p.activities.contains { $0.unitId == "g-t" }, "the revisited unit is practised")
        assertWellFormed(p, real, maxCount: 16)
    }

    // MARK: Struggling

    func testStruggleStepsBackAndAddsAGuidedEasierVersion() {
        var snap: LearnerSnapshot = snapshotWithSecure(index: real.index, upTo: 30)
        var struggling: SkillState = SkillState(unitId: "g-qu", track: .recognise)
        struggling.status = .learning
        struggling.struggleStreak = SessionPlanner.struggleThreshold
        snap.skills.append(struggling)
        let p: SessionPlan = plan(real, snap, now: day(1), seed: 3)
        XCTAssertEqual(p.focusUnitId, "g-qu")
        XCTAssertFalse(p.modelledKeys.isEmpty)
        XCTAssertTrue(p.reasons.contains { $0.hasPrefix("Stepping back") })
        for k in p.modelledKeys {
            XCTAssertTrue(k.hasSuffix("~easy"))
            guard let a = p.activities.first(where: { $0.key == k }) else { XCTFail("missing"); continue }
            XCTAssertFalse(ActivityGenerator.modelledSteps(a).isEmpty)
        }
        // The first activities come from the earlier sounds g-qu builds on (g-u, g-ck) before the guided version.
        let prereqs: Set<String> = ["g-u", "g-ck"]
        XCTAssertTrue(p.activities.prefix(3).contains { prereqs.contains($0.unitId) })
        assertWellFormed(p, real, maxCount: 16)
    }

    func testRecoveryGivesAnEasierGuidedItemPlusAnEarlierSound() throws {
        let p: SessionPlan = plan(real, snapshotWithSecure(index: real.index, upTo: 30), now: day(40), seed: 2)
        let focusId: String = p.focusUnitId ?? ""
        let a: Activity = try XCTUnwrap(p.activities.first(where: { $0.unitId == focusId }))
        let r: SessionRecovery = SessionPlanner.recovery(index: real.index, snapshot: makeSnapshot(), activity: a, now: day(40), seed: 4)
        XCTAssertGreaterThanOrEqual(r.activities.count, 1)
        XCTAssertTrue(r.activities[0].key.hasSuffix("~easy"))
        XCTAssertEqual(r.modelledKeys, [r.activities[0].key])
        XCTAssertGreaterThanOrEqual(r.activities.count, 2)
        XCTAssertFalse(r.reason.isEmpty)
    }

    /// Every answer wrong, session after session: planning always terminates, always yields a bounded, valid session,
    /// never repeats an item more than 3 times, and starts offering guided easier versions.
    private func simulateAllWrong(_ data: RealData, start: LearnerSnapshot, sessions: Int, firstDay: Int) {
        var snap: LearnerSnapshot = start
        let settings: MasterySettings = snap.profile.settings.mastery
        var sawGuided: Bool = false
        var distinctKeys: Set<String> = []
        for s in 0..<sessions {
            let now: Date = day(firstDay + s)
            let p: SessionPlan = plan(data, snap, now: now, seed: UInt64(100 + s))
            assertWellFormed(p, data, maxCount: 17)
            if !p.modelledKeys.isEmpty { sawGuided = true }
            for a in p.activities {
                distinctKeys.insert(a.key)
                let attempt: Attempt = Attempt(at: now, sessionId: p.id, unitId: a.unitId, track: a.track, activityType: a.type,
                                               itemKey: a.key, correct: false, support: .independent)
                if let i = snap.skills.firstIndex(where: { $0.unitId == a.unitId && $0.track == a.track }) {
                    snap.skills[i] = Mastery.update(skill: snap.skills[i], attempt: attempt, settings: settings, now: now)
                } else {
                    snap.skills.append(Mastery.update(skill: SkillState(unitId: a.unitId, track: a.track), attempt: attempt, settings: settings, now: now))
                }
                snap.attempts.append(attempt)
            }
        }
        XCTAssertTrue(sawGuided, "a child who keeps missing must be offered guided, easier versions")
        XCTAssertGreaterThan(distinctKeys.count, 4, "must not loop on a handful of items")
        let startKeys: Set<String> = Set(start.skills.map { $0.unitId + "|" + $0.track.rawValue })
        for sk in snap.skills where !startKeys.contains(sk.unitId + "|" + sk.track.rawValue) {
            XCTAssertNotEqual(sk.status, .secure, "answering everything wrongly can never create mastery")
        }
    }

    func testAllWrongAnswersNeverTrapTheLearnerFixture() {
        simulateAllWrong(fx, start: makeSnapshot(), sessions: 8, firstDay: 0)
    }

    func testAllWrongAnswersNeverTrapTheLearnerRealFromStart() {
        simulateAllWrong(real, start: makeSnapshot(), sessions: 6, firstDay: 0)
    }

    func testAllWrongAnswersNeverTrapTheLearnerRealMidCurriculum() {
        simulateAllWrong(real, start: snapshotWithSecure(index: real.index, upTo: 25), sessions: 5, firstDay: 40)
    }

    // MARK: Baseline plan

    func testBaselinePlanIsShortOrderedAndValid() {
        let plan: BaselinePlan = Baseline.plan(index: real.index, seed: 3)
        XCTAssertGreaterThanOrEqual(plan.activities.count, 12)
        XCTAssertLessThanOrEqual(plan.activities.count, 18)
        XCTAssertEqual(plan.stopAfterConsecutiveMisses, 2)
        var last: Int = 0
        for a in plan.activities {
            let order: Int = real.index.unitOrder(id: a.unitId) ?? 0
            XCTAssertGreaterThan(order, last, "easiest first")
            last = order
            validateActivity(a, spec: ActivitySpec(unitId: a.unitId, type: a.type, knownOrder: order), index: real.index)
        }
        // Units 1 and 2 offer fewer than three choices (a guess passes), so the baseline starts after them.
        XCTAssertGreaterThanOrEqual(real.index.unitOrder(id: plan.activities.first?.unitId ?? "") ?? 0, 3)
        let again: BaselinePlan = Baseline.plan(index: real.index, seed: 3)
        XCTAssertEqual(plan.activities, again.activities)
    }

    func testFixtureBaselinePlan() {
        let plan: BaselinePlan = Baseline.plan(index: fx.index, seed: 1)
        XCTAssertFalse(plan.activities.isEmpty)
        XCTAssertLessThanOrEqual(plan.activities.count, 9)
        for a in plan.activities {
            validateActivity(a, spec: ActivitySpec(unitId: a.unitId, type: a.type, knownOrder: fx.index.unitOrder(id: a.unitId) ?? 0), index: fx.index)
        }
    }
}
