import XCTest
@testable import StorySoundsCore

/// Local-day keys, the post-secure error window, single-choice evidence and usable parent overrides.
final class EngineHardeningTests: XCTestCase {
    private var fx: RealData { return TestData.fixture }
    private var real: RealData { return TestData.real }

    private func zone(_ id: String) throws -> TimeZone {
        return try XCTUnwrap(TimeZone(identifier: id), "time zone \(id) unavailable")
    }

    private func date(_ tz: TimeZone, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) throws -> Date {
        var cal: Calendar = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return try XCTUnwrap(cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)))
    }

    // MARK: Day key = local calendar day

    func testDayKeyFollowsTheInjectedTimeZone() throws {
        // 2023-11-14 22:13:20 UTC
        let instant: Date = Date(timeIntervalSince1970: 1_700_000_000)
        let sydney: TimeZone = try zone("Australia/Sydney")
        let auckland: TimeZone = try zone("Pacific/Auckland")
        let la: TimeZone = try zone("America/Los_Angeles")
        let kiritimati: TimeZone = try zone("Pacific/Kiritimati")
        let pagoPago: TimeZone = try zone("Pacific/Pago_Pago")
        XCTAssertEqual(DayKey.string(for: instant, timeZone: DayKey.utc), "2023-11-14")
        XCTAssertEqual(DayKey.string(for: instant, timeZone: sydney), "2023-11-15")
        XCTAssertEqual(DayKey.string(for: instant, timeZone: auckland), "2023-11-15")
        XCTAssertEqual(DayKey.string(for: instant, timeZone: la), "2023-11-14")
        XCTAssertEqual(DayKey.string(for: instant, timeZone: kiritimati), "2023-11-15")
        XCTAssertEqual(DayKey.string(for: instant, timeZone: pagoPago), "2023-11-14")
    }

    func testDayKeyDefaultsToTheDeviceTimeZone() {
        let instant: Date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(DayKey.string(for: instant), DayKey.string(for: instant, timeZone: TimeZone.current))
    }

    func testDayKeyAcceptsACalendar() throws {
        var cal: Calendar = Calendar(identifier: .gregorian)
        cal.timeZone = try zone("Australia/Sydney")
        XCTAssertEqual(DayKey.string(for: Date(timeIntervalSince1970: 1_700_000_000), calendar: cal), "2023-11-15")
    }

    func testMorningAndEveningInSydneyAreOneLocalDayButTwoUTCDays() throws {
        let sydney: TimeZone = try zone("Australia/Sydney")
        let morning: Date = try date(sydney, 2023, 11, 15, 8)
        let evening: Date = try date(sydney, 2023, 11, 15, 18)
        XCTAssertEqual(DayKey.string(for: morning, timeZone: sydney), DayKey.string(for: evening, timeZone: sydney))
        XCTAssertNotEqual(DayKey.string(for: morning, timeZone: DayKey.utc), DayKey.string(for: evening, timeZone: DayKey.utc))
    }

    func testAnEveningSessionAcrossUTCMidnightInTheUSIsOneDay() throws {
        let la: TimeZone = try zone("America/Los_Angeles")
        let early: Date = try date(la, 2023, 11, 14, 15, 50)   // 23:50 UTC
        let late: Date = try date(la, 2023, 11, 14, 16, 10)    // 00:10 UTC next day
        XCTAssertEqual(DayKey.string(for: early, timeZone: la), DayKey.string(for: late, timeZone: la))
        XCTAssertNotEqual(DayKey.string(for: early, timeZone: DayKey.utc), DayKey.string(for: late, timeZone: DayKey.utc))
    }

    func testMasteryCountsLocalDaysWhenGivenATimeZone() throws {
        let sydney: TimeZone = try zone("Australia/Sydney")
        let morning: Date = try date(sydney, 2023, 11, 15, 8)
        let evening: Date = try date(sydney, 2023, 11, 15, 18)
        func run(_ tz: TimeZone) -> SkillState {
            var s: SkillState = SkillState(unitId: "g-s", track: .recognise)
            for at in [morning, evening] {
                s = Mastery.update(skill: s, attempt: makeAttempt(correct: true, session: "x", at: at), settings: MasterySettings(), now: at, timeZone: tz)
            }
            return s
        }
        XCTAssertEqual(run(sydney).daysSeen, ["2023-11-15"], "one family day is one day of evidence")
        XCTAssertEqual(run(DayKey.utc).daysSeen.count, 2, "the old UTC key would have counted two")
    }

    // MARK: Errors before the skill became secure never count against it

    private func securedWithAnEarlyMiss() -> SkillState {
        let steps: [Step] = [
            (true, "a", 0, .listenChooseSound), (false, "a", 0, .findGrapheme), (true, "a", 0, .listenChooseSound),
            (true, "a", 0, .findGrapheme), (true, "b", 1, .listenChooseSound), (true, "b", 1, .findGrapheme),
        ]
        return feed(SkillState(unitId: "g-s", track: .recognise), steps)
    }

    func testSecuringWithAnEarlierMissStartsAFreshErrorWindow() {
        let s: SkillState = securedWithAnEarlyMiss()
        XCTAssertEqual(s.status, .secure, "one error in the window is allowed")
        XCTAssertTrue(s.recentResults.isEmpty, "only errors made since the skill became secure may count")
    }

    func testFirstErrorAfterSecuringDoesNotDemoteEvenWithAnEarlierMiss() {
        var s: SkillState = securedWithAnEarlyMiss()
        s = feed(s, [(true, "b", 1, .listenChooseSound), (true, "b", 2, .findGrapheme), (true, "c", 2, .listenChooseSound)])
        s.reviewStage = 2
        s = Mastery.update(skill: s, attempt: makeAttempt(correct: false, session: "c", at: day(3)), settings: MasterySettings(), now: day(3))
        XCTAssertEqual(s.status, .secure, "one occasional error never erases progress")
        XCTAssertEqual(s.reviewStage, 1)
    }

    func testTwoErrorsAfterSecuringStillDemote() {
        var s: SkillState = securedWithAnEarlyMiss()
        for _ in 0..<2 {
            s = Mastery.update(skill: s, attempt: makeAttempt(correct: false, session: "c", at: day(3)), settings: MasterySettings(), now: day(3))
        }
        XCTAssertEqual(s.status, .reviewDue)
        XCTAssertEqual(s.reviewStage, 0)
    }

    func testRecoveringFromReviewDueAlsoStartsAFreshWindow() {
        var s: SkillState = secureSkill("g-s", .recognise)
        for _ in 0..<2 { s = Mastery.update(skill: s, attempt: makeAttempt(correct: false, session: "c", at: day(3)), settings: MasterySettings(), now: day(3)) }
        XCTAssertEqual(s.status, .reviewDue)
        for i in 0..<12 where s.status != .secure {
            s = Mastery.update(skill: s, attempt: makeAttempt(correct: true, session: "d", at: day(4 + i)), settings: MasterySettings(), now: day(4 + i))
        }
        XCTAssertEqual(s.status, .secure)
        XCTAssertTrue(s.recentResults.isEmpty, "the moment of recovery starts a fresh error window")
    }

    // MARK: Single-choice items are not independent evidence

    func testOnlyUnitOneHasOneChoiceRecognition() {
        for data in [fx, real] {
            let first: String = data.index.units[0].id
            XCTAssertTrue(data.index.hasOnlyOneChoiceRecognition(unitId: first))
            for u in data.index.units.dropFirst() { XCTAssertFalse(data.index.hasOnlyOneChoiceRecognition(unitId: u.id), u.id) }
        }
    }

    func testEverySingleChoiceItemInAPlanIsPresentedAsModelled() {
        for data in [fx, real] {
            let p: SessionPlan = SessionPlanner.plan(index: data.index, snapshot: makeSnapshot(), now: day(0), seed: 1, minutes: 7, focusUnitId: nil)
            let single: [Activity] = p.activities.filter { ActivityGenerator.isSingleChoice($0) }
            XCTAssertFalse(single.isEmpty, "unit 1 only has one-choice recognise items")
            for a in single { XCTAssertTrue(p.modelledKeys.contains(a.key), "\(a.key) would count as independent evidence") }
        }
    }

    func testPlansWithRealChoicesAreNotMarkedModelled() {
        let snap: LearnerSnapshot = snapshotWithSecure(index: real.index, upTo: 20)
        let p: SessionPlan = SessionPlanner.plan(index: real.index, snapshot: snap, now: day(40), seed: 3, minutes: 7, focusUnitId: nil)
        XCTAssertTrue(p.activities.allSatisfy { !ActivityGenerator.isSingleChoice($0) })
        XCTAssertTrue(p.modelledKeys.isEmpty)
    }

    func testRecoveryMarksSingleChoiceItemsModelled() throws {
        let plan: SessionPlan = SessionPlanner.plan(index: real.index, snapshot: makeSnapshot(), now: day(0), seed: 1, minutes: 7, focusUnitId: nil)
        let a: Activity = try XCTUnwrap(plan.activities.first(where: { ActivityGenerator.isSingleChoice($0) }))
        let r: SessionRecovery = SessionPlanner.recovery(index: real.index, snapshot: makeSnapshot(), activity: a, now: day(0), seed: 2)
        for x in r.activities where ActivityGenerator.isSingleChoice(x) { XCTAssertTrue(r.modelledKeys.contains(x.key)) }
    }

    func testUnitOneDoesNotBlockTheSequenceOnceTheLearnerHasMetIt() {
        for data in [fx, real] {
            let idx: CurriculumIndex = data.index
            let first: GraphemeUnit = idx.units[0]
            let second: String = idx.units[1].id
            XCTAssertEqual(Progression.nextUnit(index: idx, snapshot: makeSnapshot(), now: day(1))?.id, first.id, "not met yet: taught first")
            // Modelled attempts create the skill in `.learning` without any independent evidence.
            var met: SkillState = SkillState(unitId: first.id, track: .recognise)
            met = Mastery.update(skill: met, attempt: makeAttempt(unit: first.id, correct: true, support: .modelled), settings: MasterySettings(), now: day(0))
            XCTAssertEqual(met.status, .learning)
            XCTAssertEqual(met.attempts, 0)
            var snap: LearnerSnapshot = makeSnapshot()
            snap.skills = [met]
            XCTAssertEqual(Progression.nextUnit(index: idx, snapshot: snap, now: day(1))?.id, second, "no deadlock at unit 1")
        }
    }

    func testLaterUnitsStillNeedRealIndependentEvidence() {
        let idx: CurriculumIndex = fx.index
        // g-t is the first unit with three choices; units 1 and 2 only offer one or two (see EngineReviewFixesTests).
        var snap: LearnerSnapshot = snapshotWithSecure(index: idx, upTo: 2)
        var met: SkillState = SkillState(unitId: "g-t", track: .recognise)
        met = Mastery.update(skill: met, attempt: makeAttempt(unit: "g-t", correct: true, support: .modelled), settings: MasterySettings(), now: day(0))
        snap.skills.append(met)
        XCTAssertEqual(Progression.nextUnit(index: idx, snapshot: snap, now: day(1))?.id, "g-t", "modelled help alone does not pass g-t")
    }

    // MARK: Parent overrides change what is planned

    private func unlockedSnapshot(upTo: Int, unlock: [(String, Int)]) -> LearnerSnapshot {
        var snap: LearnerSnapshot = snapshotWithSecure(index: fx.index, upTo: upTo)
        snap.profile.overrides = unlock.map { ParentOverride(unitId: $0.0, mode: .unlocked, at: day($0.1)) }
        return snap
    }

    func testUnlockedUnitBecomesTheFocusAndTheFrontierIsUnchanged() {
        let snap: LearnerSnapshot = unlockedSnapshot(upTo: 1, unlock: [("g-p", 1)])
        XCTAssertEqual(Progression.nextUnit(index: fx.index, snapshot: snap, now: day(2))?.id, "g-a", "the three-argument form is the natural frontier")
        XCTAssertEqual(Progression.overrideFocusUnit(index: fx.index, snapshot: snap, now: day(2))?.id, "g-p")
        XCTAssertEqual(Progression.nextUnit(index: fx.index, snapshot: snap, now: day(2), focusUnitId: nil)?.id, "g-p")
        XCTAssertEqual(Progression.nextUnit(index: fx.index, snapshot: snap, now: day(2), focusUnitId: "g-t")?.id, "g-t", "an explicit focus wins")
        XCTAssertEqual(Progression.nextUnit(index: fx.index, snapshot: snap, now: day(2), focusUnitId: "nope")?.id, "g-p", "unknown explicit unit is ignored")
    }

    func testPlannerPlansForTheUnlockedUnit() {
        let snap: LearnerSnapshot = unlockedSnapshot(upTo: 1, unlock: [("g-p", 1)])
        let skillsBefore: [SkillState] = snap.skills
        let p: SessionPlan = SessionPlanner.plan(index: fx.index, snapshot: snap, now: day(2), seed: 5, minutes: 7, focusUnitId: nil)
        XCTAssertEqual(p.focusUnitId, "g-p")
        XCTAssertEqual(p.knownOrder, 4)
        XCTAssertTrue(p.activities.contains { $0.unitId == "g-p" })
        XCTAssertTrue(p.reasons.contains { $0.contains("grown-up unlocked") })
        XCTAssertEqual(snap.skills, skillsBefore, "planning never edits mastery evidence")
        for a in p.activities { validateActivity(a, spec: ActivitySpec(unitId: a.unitId, type: a.type, knownOrder: p.knownOrder), index: fx.index) }
    }

    func testNewestUnlockWinsAndRevisitNeverSteersTheFocus() {
        var snap: LearnerSnapshot = unlockedSnapshot(upTo: 1, unlock: [("g-t", 1), ("g-p", 2)])
        XCTAssertEqual(Progression.overrideFocusUnit(index: fx.index, snapshot: snap, now: day(3))?.id, "g-p")
        snap.profile.overrides.append(ParentOverride(unitId: "g-p", mode: .revisit, at: day(3)))
        XCTAssertEqual(Progression.overrideFocusUnit(index: fx.index, snapshot: snap, now: day(3))?.id, "g-t", "g-p's latest override is now a revisit")
        var onlyRevisit: LearnerSnapshot = snapshotWithSecure(index: fx.index, upTo: 1)
        onlyRevisit.profile.overrides = [ParentOverride(unitId: "g-s", mode: .revisit, at: day(1))]
        XCTAssertNil(Progression.overrideFocusUnit(index: fx.index, snapshot: onlyRevisit, now: day(2)))
    }

    func testUnlockOfASecureUnitOrAnOverusedOverrideStopsSteering() {
        var snap: LearnerSnapshot = unlockedSnapshot(upTo: 2, unlock: [("g-a", 1)])
        XCTAssertNil(Progression.overrideFocusUnit(index: fx.index, snapshot: snap, now: day(2)), "g-a is already secure")
        snap = unlockedSnapshot(upTo: 1, unlock: [("g-p", 1)])
        for i in 0..<Progression.overrideSessionCap {
            var sess: SessionSummary = SessionSummary(id: "s\(i)", startedAt: day(i))
            sess.unitsPractised = ["g-p"]
            snap.sessions.append(sess)
        }
        XCTAssertNil(Progression.overrideFocusUnit(index: fx.index, snapshot: snap, now: day(9)), "a standing override cannot pin the child forever")
        let p: SessionPlan = SessionPlanner.plan(index: fx.index, snapshot: snap, now: day(9), seed: 1, minutes: 7, focusUnitId: nil)
        XCTAssertEqual(p.focusUnitId, "g-a")
    }

    func testExplicitFocusStillBeatsAnUnlockInThePlanner() {
        let snap: LearnerSnapshot = unlockedSnapshot(upTo: 1, unlock: [("g-p", 1)])
        let p: SessionPlan = SessionPlanner.plan(index: fx.index, snapshot: snap, now: day(2), seed: 5, minutes: 7, focusUnitId: "g-t")
        XCTAssertEqual(p.focusUnitId, "g-t")
    }

    func testRevisitUnitAheadOfTheFocusIsReviewedOnceTheLearnerHasMetIt() {
        var snap: LearnerSnapshot = snapshotWithSecure(index: fx.index, upTo: 2)   // focus: g-t (order 3)
        var met: SkillState = SkillState(unitId: "g-i", track: .recognise)         // g-i is order 5, already met (e.g. via placement)
        met.status = .learning
        snap.skills.append(met)
        snap.profile.overrides = [ParentOverride(unitId: "g-i", mode: .revisit, at: day(1))]
        let p: SessionPlan = SessionPlanner.plan(index: fx.index, snapshot: snap, now: day(2), seed: 7, minutes: 7, focusUnitId: nil)
        XCTAssertEqual(p.focusUnitId, "g-t")
        XCTAssertTrue(p.activities.contains { $0.unitId == "g-i" }, "the revisit request must not be silently dropped")
        XCTAssertGreaterThanOrEqual(p.knownOrder, 5, "the plan reports the order it really draws content from")
        for a in p.activities where a.unitId == "g-i" {
            validateActivity(a, spec: ActivitySpec(unitId: "g-i", type: a.type, knownOrder: 5), index: fx.index)
        }
    }

    func testRevisitOfAUnitTheLearnerNeverMetDoesNotLeakUntaughtContent() {
        var snap: LearnerSnapshot = snapshotWithSecure(index: fx.index, upTo: 2)
        snap.profile.overrides = [ParentOverride(unitId: "g-i", mode: .revisit, at: day(1))]
        let p: SessionPlan = SessionPlanner.plan(index: fx.index, snapshot: snap, now: day(2), seed: 7, minutes: 7, focusUnitId: nil)
        XCTAssertFalse(p.activities.contains { $0.unitId == "g-i" })
        XCTAssertEqual(p.knownOrder, 3)
    }
}
