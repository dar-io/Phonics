import XCTest
@testable import StorySoundsCore

final class ProgressionTests: XCTestCase {
    private var fx: CurriculumIndex { return TestData.fixture.index }
    private var real: CurriculumIndex { return TestData.real.index }

    private func explain(_ index: CurriculumIndex, _ snap: LearnerSnapshot, now: Date = day(1)) -> [String: UnitExplanation] {
        var m: [String: UnitExplanation] = [:]
        for e in Progression.explainUnits(index: index, snapshot: snap, now: now) { m[e.unitId] = e }
        return m
    }

    // MARK: Locking and explanations (fixture)

    func testFreshLearnerHasOneAvailableUnitAndTheRestLocked() {
        let snap: LearnerSnapshot = makeSnapshot()
        let e: [String: UnitExplanation] = explain(fx, snap)
        XCTAssertEqual(Progression.nextUnit(index: fx, snapshot: snap, now: day(1))?.id, "g-s")
        XCTAssertEqual(e["g-s"]?.status, .available)
        XCTAssertEqual(e["g-a"]?.status, .locked)
        XCTAssertEqual(e["g-a"]?.blockedBy, ["g-s"])
        let reason: String = e["g-a"]?.reason ?? ""
        XCTAssertTrue(reason.contains("/s/"), reason)
        XCTAssertTrue(reason.contains("'s'"), reason)
        XCTAssertEqual(e["g-a-ai"]?.blockedBy, ["g-ai", "g-a"])
        for (id, x) in e where id != "g-s" { XCTAssertEqual(x.status, .locked, id) }
    }

    func testSecureGateTrackUnlocksTheNextUnit() {
        let snap: LearnerSnapshot = snapshotWithSecure(index: fx, upTo: 1)
        let e: [String: UnitExplanation] = explain(fx, snap)
        XCTAssertEqual(Progression.nextUnit(index: fx, snapshot: snap, now: day(1))?.id, "g-a")
        XCTAssertEqual(e["g-s"]?.status, .inProgress, "recognise is secure but reading is not")
        XCTAssertEqual(e["g-a"]?.status, .available)
        XCTAssertEqual(e["g-t"]?.status, .locked)
        XCTAssertTrue((e["g-t"]?.reason ?? "").contains("/a/"))
    }

    func testMasteredNeedsEveryApplicableTrack() {
        let snap: LearnerSnapshot = snapshotWithSecure(index: fx, upTo: 1, allTracks: true)
        XCTAssertEqual(explain(fx, snap)["g-s"]?.status, .mastered)
    }

    func testNotSecureUntilEvidenceIsStrongEnough() {
        var snap: LearnerSnapshot = makeSnapshot()
        let half: SkillState = feed(SkillState(unitId: "g-s", track: .recognise), Array(secureSteps().prefix(4)))
        snap.skills = [half]
        let e: [String: UnitExplanation] = explain(fx, snap)
        XCTAssertEqual(e["g-s"]?.status, .inProgress)
        XCTAssertEqual(e["g-a"]?.status, .locked)
        XCTAssertEqual(Progression.nextUnit(index: fx, snapshot: snap, now: day(1))?.id, "g-s")
    }

    func testDueReviewShowsAsReviewDueButDoesNotRelockLaterUnits() {
        let snap: LearnerSnapshot = snapshotWithSecure(index: fx, upTo: 2)
        let e: [String: UnitExplanation] = explain(fx, snap, now: day(30))
        XCTAssertEqual(e["g-s"]?.status, .reviewDue)
        XCTAssertEqual(e["g-a"]?.status, .reviewDue)
        XCTAssertEqual(e["g-t"]?.status, .available)
        XCTAssertEqual(Progression.nextUnit(index: fx, snapshot: snap, now: day(30))?.id, "g-t")
    }

    func testDemotedSkillStillCountsAsPassedForProgression() {
        var snap: LearnerSnapshot = snapshotWithSecure(index: fx, upTo: 1)
        snap.skills[0].status = .reviewDue
        XCTAssertEqual(Progression.nextUnit(index: fx, snapshot: snap, now: day(1))?.id, "g-a")
    }

    func testOneNewUnitAtATimeThroughTheWholeFixtureSequence() {
        let units: [GraphemeUnit] = fx.units
        for (i, u) in units.enumerated() {
            let upTo: Int = i == 0 ? 0 : units[i - 1].order
            let snap: LearnerSnapshot = snapshotWithSecure(index: fx, upTo: upTo)
            XCTAssertEqual(Progression.nextUnit(index: fx, snapshot: snap, now: day(1))?.id, u.id)
        }
        XCTAssertNil(Progression.nextUnit(index: fx, snapshot: snapshotWithSecure(index: fx, upTo: 99), now: day(1)))
    }

    // MARK: Parent overrides

    func testOverridesChangeAvailabilityButNeverTouchSkills() {
        var snap: LearnerSnapshot = snapshotWithSecure(index: fx, upTo: 1)
        let skillsBefore: [SkillState] = snap.skills
        let nextBefore: String? = Progression.nextUnit(index: fx, snapshot: snap, now: day(1))?.id

        snap.profile.overrides = [
            ParentOverride(unitId: "g-p", mode: .unlocked, at: day(1)),
            ParentOverride(unitId: "g-s", mode: .revisit, at: day(1)),
        ]
        let e: [String: UnitExplanation] = explain(fx, snap)
        XCTAssertEqual(e["g-p"]?.status, .available, "unlocked skips the prerequisite lock")
        XCTAssertTrue((e["g-p"]?.reason ?? "").contains("grown-up"))
        XCTAssertEqual(e["g-s"]?.status, .reviewDue, "revisit marks for practice")
        XCTAssertTrue((e["g-s"]?.reason ?? "").contains("practised again"))
        XCTAssertEqual(e["g-t"]?.status, .locked, "other units are unaffected")

        XCTAssertEqual(snap.skills, skillsBefore)
        for s in snap.skills { XCTAssertTrue(Mastery.isSecure(s, settings: snap.profile.settings.mastery) || s.status == .secure) }
        XCTAssertEqual(Progression.nextUnit(index: fx, snapshot: snap, now: day(1))?.id, nextBefore, "overrides never skip ahead silently")
        XCTAssertEqual(Progression.revisitUnitIds(snap), ["g-s"])
    }

    func testLatestOverrideWins() {
        var snap: LearnerSnapshot = makeSnapshot()
        snap.profile.overrides = [
            ParentOverride(unitId: "g-t", mode: .revisit, at: day(1)),
            ParentOverride(unitId: "g-t", mode: .unlocked, at: day(2)),
        ]
        XCTAssertEqual(Progression.latestOverrides(snap)["g-t"], .unlocked)
        XCTAssertEqual(explain(fx, snap)["g-t"]?.status, .available)
        XCTAssertTrue(Progression.revisitUnitIds(snap).isEmpty)
        snap.profile.overrides.append(ParentOverride(unitId: "g-t", mode: .revisit, at: day(3)))
        XCTAssertEqual(Progression.latestOverrides(snap)["g-t"], .revisit)
    }

    func testRevisitOnALockedUnitDoesNotOpenIt() {
        var snap: LearnerSnapshot = makeSnapshot()
        snap.profile.overrides = [ParentOverride(unitId: "g-t", mode: .revisit, at: day(1))]
        XCTAssertEqual(explain(fx, snap)["g-t"]?.status, .locked)
    }

    // MARK: Baseline placement (fixture)

    func testBaselinePlacesAtEarliestUnprovenPrerequisiteNotHighestCorrect() {
        let results: [BaselineItemResult] = [
            BaselineItemResult(unitId: "g-s", correct: true),
            BaselineItemResult(unitId: "g-t", correct: true),
            BaselineItemResult(unitId: "g-n", correct: false),
            BaselineItemResult(unitId: "g-sh", correct: true),
            BaselineItemResult(unitId: "g-ai", correct: true),
        ]
        let p: BaselinePlacement = Progression.placeFromBaseline(index: fx, results: results, now: day(0))
        // Missed g-n (6); its prerequisite g-i (5) was never shown to be known, so we start there, well below g-ai (8).
        XCTAssertEqual(p.placementUnitId, "g-i")
        XCTAssertEqual(p.placementOrder, 5)
        XCTAssertEqual(Set(p.provisionalSkills.map { $0.unitId }), ["g-s", "g-a", "g-t", "g-p"])
        for s in p.provisionalSkills {
            XCTAssertEqual(s.status, .learning, "provisional evidence is never secure")
            XCTAssertFalse(Mastery.isSecure(s, settings: MasterySettings()))
            XCTAssertNotNil(s.nextReviewAt)
        }
        let proven: SkillState? = p.provisionalSkills.first(where: { $0.unitId == "g-t" })
        let unproven: SkillState? = p.provisionalSkills.first(where: { $0.unitId == "g-a" })
        XCTAssertGreaterThan(proven?.score ?? 0, unproven?.score ?? 1)

        let snap: LearnerSnapshot = Progression.applyPlacement(p, to: makeSnapshot())
        XCTAssertTrue(snap.profile.baselineDone)
        XCTAssertEqual(snap.profile.baselinePlacementOrder, 5)
        XCTAssertEqual(Progression.nextUnit(index: fx, snapshot: snap, now: day(1))?.id, "g-i")
        let e: [String: UnitExplanation] = explain(fx, snap)
        XCTAssertEqual(e["g-i"]?.status, .available)
        XCTAssertEqual(e["g-n"]?.status, .locked)
        XCTAssertEqual(e["g-s"]?.status, .inProgress, "placed past, revisited gently")
    }

    func testApplyPlacementKeepsExistingEvidence() {
        var snap: LearnerSnapshot = makeSnapshot()
        let existing: SkillState = secureSkill("g-s", .recognise)
        snap.skills = [existing]
        let p: BaselinePlacement = Progression.placeFromBaseline(index: fx, results: [
            BaselineItemResult(unitId: "g-s", correct: true), BaselineItemResult(unitId: "g-p", correct: false),
        ], now: day(2))
        let applied: LearnerSnapshot = Progression.applyPlacement(p, to: snap)
        XCTAssertTrue(applied.skills.contains(existing))
        XCTAssertEqual(applied.skills.filter { $0.unitId == "g-s" && $0.track == .recognise }.count, 1)
    }

    func testBaselineEdgeCases() {
        // Everything right: start at the highest sampled unit.
        let allRight: BaselinePlacement = Progression.placeFromBaseline(index: fx, results: [
            BaselineItemResult(unitId: "g-s", correct: true), BaselineItemResult(unitId: "g-p", correct: true),
            BaselineItemResult(unitId: "g-sh", correct: true),
        ], now: day(0))
        XCTAssertEqual(allRight.placementUnitId, "g-sh")
        // A prompted answer is a miss.
        let prompted: BaselinePlacement = Progression.placeFromBaseline(index: fx, results: [
            BaselineItemResult(unitId: "g-s", correct: true), BaselineItemResult(unitId: "g-a", correct: true, support: .prompted),
        ], now: day(0))
        XCTAssertEqual(prompted.placementUnitId, "g-a")
        // No usable results: start at the beginning.
        let none: BaselinePlacement = Progression.placeFromBaseline(index: fx, results: [BaselineItemResult(unitId: "nope", correct: true)], now: day(0))
        XCTAssertEqual(none.placementOrder, 1)
        XCTAssertTrue(none.provisionalSkills.isEmpty)
        // One miss anywhere in a unit makes the unit a miss.
        let mixed: BaselinePlacement = Progression.placeFromBaseline(index: fx, results: [
            BaselineItemResult(unitId: "g-s", correct: true), BaselineItemResult(unitId: "g-s", correct: false),
        ], now: day(0))
        XCTAssertEqual(mixed.placementUnitId, "g-s")
    }

    func testBaselineStopsAfterTwoConsecutiveIndependentMisses() {
        func r(_ c: Bool, _ s: SupportLevel = .independent) -> BaselineItemResult { return BaselineItemResult(unitId: "g-s", correct: c, support: s) }
        XCTAssertFalse(Baseline.shouldStop(results: []))
        XCTAssertFalse(Baseline.shouldStop(results: [r(false)]))
        XCTAssertTrue(Baseline.shouldStop(results: [r(false), r(false)]))
        XCTAssertFalse(Baseline.shouldStop(results: [r(false), r(true), r(false)]))
        XCTAssertTrue(Baseline.shouldStop(results: [r(true), r(false), r(false)]))
        XCTAssertTrue(Baseline.shouldStop(results: [r(true), r(true, .prompted), r(false)]))
    }

    // MARK: Real data

    func testRealFreshLearnerHasExactlyOneAvailableUnit() {
        let snap: LearnerSnapshot = makeSnapshot()
        let all: [UnitExplanation] = Progression.explainUnits(curriculum: TestData.real.curriculum, snapshot: snap, now: day(0))
        XCTAssertEqual(all.count, real.units.count)
        XCTAssertEqual(all.filter { $0.status == .available }.map { $0.unitId }, ["g-s"])
        for e in all where e.unitId != "g-s" {
            XCTAssertEqual(e.status, .locked, e.unitId)
            XCTAssertFalse(e.blockedBy.isEmpty, e.unitId)
            XCTAssertTrue(e.reason.hasPrefix("Locked until"), e.reason)
        }
    }

    func testRealSequenceUnlocksOneUnitAtATimeAndTerminates() {
        let units: [GraphemeUnit] = real.units
        for (i, u) in units.enumerated() {
            let upTo: Int = i == 0 ? 0 : units[i - 1].order
            let snap: LearnerSnapshot = snapshotWithSecure(index: real, upTo: upTo)
            XCTAssertEqual(Progression.nextUnit(index: real, snapshot: snap, now: day(1))?.id, u.id, "after \(upTo)")
        }
        XCTAssertNil(Progression.nextUnit(index: real, snapshot: snapshotWithSecure(index: real, upTo: real.maxOrder), now: day(1)))
    }

    func testRealLockedReasonNamesTheInsecurePrerequisite() {
        let snap: LearnerSnapshot = snapshotWithSecure(index: real, upTo: 5)
        let all: [String: UnitExplanation] = explain(real, snap)
        // g-m (7) needs g-n (6), which is not secure: the explanation names that sound.
        XCTAssertEqual(all["g-m"]?.status, .locked)
        XCTAssertEqual(all["g-m"]?.blockedBy, ["g-n"])
        XCTAssertTrue((all["g-m"]?.reason ?? "").contains("/n/"))
    }

    func testRealBaselineRunPlacesBelowTheFirstMissAndNeverSecure() {
        let plan: BaselinePlan = Baseline.plan(index: real, seed: 11)
        var results: [BaselineItemResult] = []
        for a in plan.activities {
            guard let u = real.unit(id: a.unitId) else { XCTFail("unknown unit"); continue }
            results.append(BaselineItemResult(unitId: a.unitId, correct: u.order < 40))
            if Baseline.shouldStop(results: results) { break }
        }
        let p: BaselinePlacement = Baseline.score(index: real, results: results, now: day(0))
        let sampledOrders: [Int] = plan.activities.compactMap { real.unitOrder(id: $0.unitId) }
        guard let firstMiss = sampledOrders.first(where: { $0 >= 40 }) else { XCTFail("baseline never reached order 40"); return }
        XCTAssertLessThanOrEqual(p.placementOrder, firstMiss, "never placed above the first miss")
        XCTAssertGreaterThan(p.placementOrder, 1)
        XCTAssertFalse(p.provisionalSkills.isEmpty)
        for s in p.provisionalSkills {
            XCTAssertNotEqual(s.status, .secure)
            XCTAssertLessThan(real.unitOrder(id: s.unitId) ?? 0, p.placementOrder)
        }
        let snap: LearnerSnapshot = Progression.applyPlacement(p, to: makeSnapshot())
        XCTAssertEqual(Progression.nextUnit(index: real, snapshot: snap, now: day(1))?.order, p.placementOrder)
    }
}
