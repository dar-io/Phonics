import XCTest
@testable import StorySoundsCore

/// Engine fixes from the independent pedagogy review: B1 (per-word sound), B2 (soft pass), M1 (baseline), M2 (homophones and
/// ambiguous cloze), M4 (p4-suffix), M5 (guessable first units).
final class EngineReviewFixesTests: XCTestCase {
    private var fx: RealData { return TestData.fixture }
    private var real: RealData { return TestData.real }

    private func generate(_ data: RealData, unit: String, type: ActivityType, known: Int? = nil, seed: UInt64, choices: Int = 3) -> Activity? {
        var rng: SeededRNG = SeededRNG(seed: seed)
        let order: Int = known ?? (data.index.unitOrder(id: unit) ?? 0)
        let spec: ActivitySpec = ActivitySpec(unitId: unit, type: type, knownOrder: order, choiceCount: choices)
        return ActivityGenerator.generate(curriculum: data.curriculum, index: data.index, spec: spec, rng: &rng)
    }

    // MARK: B1 per-word sound

    func testPerWordSoundFollowsTheUnitTheWordRequires() throws {
        let idx: CurriculumIndex = real.index
        func audio(_ g: String, _ w: String) -> String? { return idx.audioId(forGrapheme: g, inWord: w) }
        func unitAudio(_ id: String) throws -> String { return try XCTUnwrap(idx.unit(id: id), id).audioId }
        XCTAssertEqual(audio("o", "cold"), try unitAudio("g-o-oa"))
        XCTAssertEqual(audio("o", "hot"), try unitAudio("g-o"))
        XCTAssertEqual(audio("oo", "book"), try unitAudio("g-oo-short"))
        XCTAssertEqual(audio("oo", "moon"), try unitAudio("g-oo-long"))
        XCTAssertEqual(audio("ow", "snow"), try unitAudio("g-ow-oa"))
        XCTAssertEqual(audio("ow", "cow"), try unitAudio("g-ow"))
        XCTAssertEqual(audio("o", "COLD"), try unitAudio("g-o-oa"), "word lookup is case-insensitive")
        XCTAssertNil(audio("zzz", "cold"), "a grapheme no unit teaches has no sound")
        // The old first-taught API still exists and still answers with the first unit.
        XCTAssertEqual(idx.audioId(forGrapheme: "o", atOrder: idx.maxOrder), try unitAudio("g-o"))

        // Fixture: "spa" requires g-a-ai, so its a is /ai/ while the a in "sat" is the plain /a/.
        XCTAssertEqual(fx.index.audioId(forGrapheme: "a", inWord: "spa"), "ph-g-a-ai")
        XCTAssertEqual(fx.index.audioId(forGrapheme: "a", inWord: "sat"), "ph-g-a")
    }

    func testSweepOfEveryRealWordResolvesToTheRequiredUnitsSound() {
        let idx: CurriculumIndex = real.index
        let c: Curriculum = real.curriculum
        var firstUnit: [String: GraphemeUnit] = [:]
        var readings: [String: Int] = [:]
        for u in idx.units where !idx.isConsolidation(u) {
            for g in u.graphemes {
                if firstUnit[g] == nil { firstUnit[g] = u }
                readings[g, default: 0] += 1
            }
        }
        var alternativeWords: Int = 0
        var defaultWords: Int = 0
        var seen: Set<String> = []
        var mismatches: [String] = []
        for w in c.words {
            let key: String = w.text.lowercased()
            if !seen.insert(key).inserted { continue }
            let reqs: [String] = c.wordRequirements[key] ?? []
            var usesAlternative: Bool = false
            var resolvedByDefaultDespiteManyReadings: Bool = false
            for g in w.graphemes {
                var expected: GraphemeUnit? = nil
                for r in reqs {
                    guard let u = idx.unit(id: r), !idx.isConsolidation(u), u.graphemes.contains(g) else { continue }
                    if let e = expected, e.order >= u.order { continue }
                    expected = u
                }
                let got: String? = idx.audioId(forGrapheme: g, inWord: w.text)
                if let e = expected {
                    if got != e.audioId { mismatches.append("\(w.text)/\(g): \(got ?? "nil") != \(e.audioId)") }
                    if e.id != firstUnit[g]?.id { usesAlternative = true }
                } else {
                    if got != firstUnit[g]?.audioId { mismatches.append("\(w.text)/\(g): default is \(got ?? "nil")") }
                    if (readings[g] ?? 0) > 1 { resolvedByDefaultDespiteManyReadings = true }
                }
            }
            if usesAlternative { alternativeWords += 1 }
            if resolvedByDefaultDespiteManyReadings { defaultWords += 1 }
        }
        print("B1 sweep: \(seen.count) words; \(alternativeWords) resolve to an alternative-sound unit via wordRequirements; "
              + "\(defaultWords) contain a multi-reading grapheme but are still resolved by default (first-taught)")
        XCTAssertTrue(mismatches.isEmpty, "\(mismatches.prefix(10))")
        XCTAssertGreaterThan(alternativeWords, 100, "the review counted about 200 words with an alternative-sound requirement")
    }

    func testBlendAudioUsesTheSoundsOfTheTargetWord() {
        guard let short = real.index.unit(id: "g-oo-short"), let long = real.index.unit(id: "g-oo-long") else { return XCTFail("units") }
        var checked: Int = 0
        for seed in 0..<40 {
            guard let a = generate(real, unit: short.id, type: .blendToWord, seed: UInt64(seed)),
                  case let .blend(graphemes, _, _, _) = a.payload, graphemes.contains("oo") else { continue }
            checked += 1
            XCTAssertTrue(a.audioIds.contains(short.audioId), "\(a.key): oo in this word is the short sound")
            XCTAssertFalse(a.audioIds.contains(long.audioId), "\(a.key): the long sound contradicts the word")
        }
        XCTAssertGreaterThan(checked, 0)
    }

    func testRepeatedSoundsInABlendAreKept() {
        // A sound sequence is never de-duplicated: m-u-m plays the m twice, so there is one sound clip per grapheme.
        for seed in 0..<20 {
            guard let a = generate(real, unit: "g-m", type: .blendToWord, known: 40, seed: UInt64(seed)),
                  case let .blend(graphemes, _, _, _) = a.payload else { continue }
            let sounds: Int = a.audioIds.filter { $0.hasPrefix("ph-") }.count
            XCTAssertEqual(sounds, graphemes.count, a.key)
        }
    }

    // MARK: B2 soft pass

    func testSettingsSavedBeforeSoftPassStillDecode() throws {
        let data: Data = try JSONEncoder().encode(MasterySettings())
        var dict: [String: Any] = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for k in ["softPassAttempts", "softPassSessions", "softPassScore"] {
            XCTAssertNotNil(dict[k], "new fields are encoded")
            dict.removeValue(forKey: k)
        }
        let old: Data = try JSONSerialization.data(withJSONObject: dict)
        let decoded: MasterySettings = try JSONDecoder().decode(MasterySettings.self, from: old)
        XCTAssertEqual(decoded, MasterySettings())
        XCTAssertEqual(decoded.softPassAttempts, 12)
        XCTAssertEqual(decoded.softPassSessions, 3)
        XCTAssertEqual(decoded.softPassScore, 0.6, accuracy: 1e-9)
        let empty: MasterySettings = try JSONDecoder().decode(MasterySettings.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, MasterySettings())
        let custom: MasterySettings = try JSONDecoder().decode(MasterySettings.self, from: Data("{\"minAttempts\":9,\"softPassScore\":0.7}".utf8))
        XCTAssertEqual(custom.minAttempts, 9)
        XCTAssertEqual(custom.softPassScore, 0.7, accuracy: 1e-9)
        XCTAssertEqual(custom.secureScore, 0.85, accuracy: 1e-9)
    }

    func testSoftPassNeedsAttemptsSessionsAndScore() {
        let settings: MasterySettings = MasterySettings()
        var s: SkillState = SkillState(unitId: "g-t", track: .recognise)
        s.status = .learning
        s.attempts = 12
        s.sessionsSeen = ["a", "b", "c"]
        s.score = 0.6
        XCTAssertTrue(Progression.meetsSoftPass(s, settings: settings))
        var few: SkillState = s; few.attempts = 11
        XCTAssertFalse(Progression.meetsSoftPass(few, settings: settings))
        var oneSession: SkillState = s; oneSession.sessionsSeen = ["a", "b"]
        XCTAssertFalse(Progression.meetsSoftPass(oneSession, settings: settings))
        var low: SkillState = s; low.score = 0.59
        XCTAssertFalse(Progression.meetsSoftPass(low, settings: settings))
        var custom: MasterySettings = settings
        custom.softPassAttempts = 20
        XCTAssertFalse(Progression.meetsSoftPass(s, settings: custom))
    }

    private func softPassedFixtureSnapshot() -> LearnerSnapshot {
        var snap: LearnerSnapshot = snapshotWithSecure(index: fx.index, upTo: 2)
        var soft: SkillState = SkillState(unitId: "g-t", track: .recognise)
        soft.status = .learning
        soft.attempts = 12
        soft.sessionsSeen = ["a", "b", "c"]
        soft.score = 0.62
        snap.skills.append(soft)
        return snap
    }

    func testSoftPassedUnitIntroducesTheNextUnitButIsNotMastered() throws {
        let idx: CurriculumIndex = fx.index
        let snap: LearnerSnapshot = softPassedFixtureSnapshot()
        let before: [SkillState] = snap.skills
        let settings: MasterySettings = snap.profile.settings.mastery
        let t: GraphemeUnit = try XCTUnwrap(idx.unit(id: "g-t"))
        let skills: [String: SkillState] = Progression.skillMap(snap)

        XCTAssertFalse(Progression.isUnitSecure(unit: t, index: idx, skills: skills, settings: settings))
        XCTAssertTrue(Progression.isUnitSoftPassed(unit: t, index: idx, skills: skills, settings: settings))
        XCTAssertTrue(Progression.isUnitPassed(unit: t, index: idx, skills: skills, settings: settings))
        XCTAssertFalse(Progression.isUnitMastered(unit: t, index: idx, skills: skills, settings: settings))
        XCTAssertEqual(Progression.nextUnit(index: idx, snapshot: snap, now: day(2))?.id, "g-p", "the next unit is introduced")

        var byId: [String: UnitExplanation] = [:]
        for e in Progression.explainUnits(index: idx, snapshot: snap, now: day(2)) { byId[e.unitId] = e }
        XCTAssertEqual(byId["g-t"]?.status, .inProgress)
        XCTAssertTrue((byId["g-t"]?.reason ?? "").contains("Moving on gently"), byId["g-t"]?.reason ?? "")
        XCTAssertTrue((byId["g-t"]?.reason ?? "").contains("keep coming back for practice"))
        XCTAssertEqual(byId["g-p"]?.status, .available)
        XCTAssertEqual(snap.skills, before, "reading progression never edits evidence")

        // Parent report data lists it as developing, not mastered.
        let plain: ParentReport = ParentReport.make(curriculum: fx.curriculum, snapshot: snap, now: day(2))
        XCTAssertTrue(plain.developingUnitIds.contains("g-t"))
        XCTAssertFalse(plain.masteredUnitIds.contains("g-t"))
        var statuses: [String: UnitStatus] = [:]
        for (id, e) in byId { statuses[id] = e.status }
        let withInputs: ParentReport = ParentReport.make(curriculum: fx.curriculum, snapshot: snap, now: day(2),
                                                         inputs: ReportInputs(unitStatuses: statuses, currentUnitId: "g-p"))
        XCTAssertTrue(withInputs.developingUnitIds.contains("g-t"))
        XCTAssertFalse(withInputs.masteredUnitIds.contains("g-t"))
    }

    func testParentOverridesNeverChangeSoftPassOrSkills() {
        var snap: LearnerSnapshot = softPassedFixtureSnapshot()
        snap.profile.overrides = [ParentOverride(unitId: "g-t", mode: .revisit, at: day(1)), ParentOverride(unitId: "g-n", mode: .unlocked, at: day(1))]
        let before: [SkillState] = snap.skills
        _ = Progression.explainUnits(index: fx.index, snapshot: snap, now: day(2))
        _ = Progression.nextUnit(index: fx.index, snapshot: snap, now: day(2), focusUnitId: nil)
        _ = SessionPlanner.plan(index: fx.index, snapshot: snap, now: day(2), seed: 3, minutes: 7, focusUnitId: nil)
        XCTAssertEqual(snap.skills, before)
        XCTAssertNil(snap.skills.first(where: { $0.unitId == "g-t" })?.softPassedAt, "only evidence latches a soft pass")
    }

    func testSoftPassedSkillLatchesAndStaysInReviewAtTheShortestInterval() throws {
        // T T F repeated: 14 independent attempts over 3 sessions and 3 days; the score reaches 0.68 on attempt 13 and the
        // skill never has the clean record needed to be secure.
        let pattern: [Bool] = "TTFTTFTTFTTFTT".map { $0 == "T" }
        var steps: [Step] = []
        for (i, ok) in pattern.enumerated() {
            let sessionIndex: Int = i < 5 ? 0 : (i < 10 ? 1 : 2)
            steps.append((ok, ["a", "b", "c"][sessionIndex], sessionIndex, i % 2 == 0 ? ActivityType.listenChooseSound : ActivityType.findGrapheme))
        }
        var s: SkillState = feed(SkillState(unitId: "g-t", track: .recognise), steps)
        XCTAssertEqual(s.status, .learning, "steady effort is not mastery")
        XCTAssertNotNil(s.softPassedAt)
        XCTAssertEqual(s.nextReviewAt, Scheduler.softPassNextReviewAt(from: day(2), settings: MasterySettings()))
        XCTAssertEqual(s.nextReviewAt, day(2).addingTimeInterval(Scheduler.secondsPerDay), "shortest rung of the ladder")
        XCTAssertTrue(Scheduler.isDue(s, now: day(3)), "comes back for practice")
        XCTAssertFalse(Scheduler.isDue(s, now: day(2)))

        // A later dip never un-passes it (no flip-flopping between units).
        var wrong: [Step] = []
        for _ in 0..<6 { wrong.append((false, "c", 2, ActivityType.listenChooseSound)) }
        s = feed(s, wrong)
        XCTAssertLessThan(s.score, 0.6)
        XCTAssertTrue(Progression.meetsSoftPass(s, settings: MasterySettings()))
        XCTAssertEqual(s.status, .learning)

        // And it is picked up as a review candidate by the planner once due.
        var snap: LearnerSnapshot = snapshotWithSecure(index: fx.index, upTo: 2)
        snap.skills.append(feed(SkillState(unitId: "g-t", track: .recognise), steps))
        XCTAssertTrue(Scheduler.dueSkills(snapshot: snap, now: day(5)).contains { $0.unitId == "g-t" })
    }

    private func simulateChild(_ data: RealData, start: LearnerSnapshot, accuracyPercent: Int, sessions: Int, firstDay: Int,
                               answerSeed: UInt64) -> (snapshot: LearnerSnapshot, focusOrders: [Int]) {
        var snap: LearnerSnapshot = start
        var answers: SeededRNG = SeededRNG(seed: answerSeed)
        let settings: MasterySettings = snap.profile.settings.mastery
        var focusOrders: [Int] = []
        for s in 0..<sessions {
            let now: Date = day(firstDay + s)
            let p: SessionPlan = SessionPlanner.plan(index: data.index, snapshot: snap, now: now, seed: UInt64(500 + s), minutes: 7, focusUnitId: nil)
            focusOrders.append(data.index.unitOrder(id: p.focusUnitId ?? "") ?? 0)
            for a in p.activities where a.type != .readStory && a.type != .fluency {
                let support: SupportLevel = p.modelledKeys.contains(a.key) ? .modelled : .independent
                let correct: Bool = answers.int(below: 100) < accuracyPercent
                let attempt: Attempt = Attempt(at: now, sessionId: p.id, unitId: a.unitId, track: a.track, activityType: a.type,
                                               itemKey: a.key, correct: correct, support: support)
                if let i = snap.skills.firstIndex(where: { $0.unitId == a.unitId && $0.track == a.track }) {
                    snap.skills[i] = Mastery.update(skill: snap.skills[i], attempt: attempt, settings: settings, now: now)
                } else {
                    snap.skills.append(Mastery.update(skill: SkillState(unitId: a.unitId, track: a.track), attempt: attempt, settings: settings, now: now))
                }
            }
        }
        return (snap, focusOrders)
    }

    func testAChildAnsweringHalfRightStillMovesOnWithinBoundedSessions() throws {
        let start: LearnerSnapshot = snapshotWithSecure(index: real.index, upTo: 20)
        let startOrder: Int = 21
        let run = simulateChild(real, start: start, accuracyPercent: 50, sessions: 40, firstDay: 40, answerSeed: 4242)
        XCTAssertEqual(run.focusOrders.first, startOrder)
        guard let moved = run.focusOrders.firstIndex(where: { $0 > startOrder }) else {
            return XCTFail("a 50% child must not be trapped on unit \(startOrder) for 40 sessions: \(run.focusOrders)")
        }
        print("50% simulated child moved past unit \(startOrder) after \(moved) sessions")
        XCTAssertLessThanOrEqual(moved, 35)
        // The unit they moved on from is passed for progression, and is still being practised (never silently dropped).
        let settings: MasterySettings = run.snapshot.profile.settings.mastery
        let u: GraphemeUnit = try XCTUnwrap(real.index.units.first(where: { $0.order == startOrder }))
        XCTAssertTrue(Progression.isUnitPassed(unit: u, index: real.index, skills: Progression.skillMap(run.snapshot), settings: settings))
        XCTAssertTrue(run.snapshot.skills.contains { $0.unitId == u.id })
    }

    func testAChildWhoOnlyGuessesWrongNeverSoftPasses() {
        let start: LearnerSnapshot = snapshotWithSecure(index: real.index, upTo: 20)
        let run = simulateChild(real, start: start, accuracyPercent: 0, sessions: 12, firstDay: 40, answerSeed: 7)
        XCTAssertTrue(run.focusOrders.allSatisfy { $0 == 21 }, "effort without any accuracy does not advance: \(run.focusOrders)")
        XCTAssertFalse(run.snapshot.skills.contains { $0.softPassedAt != nil })
    }

    // MARK: M1 baseline

    func testBaselineSamplesDenselyAcrossTheWholeReceptionRange() {
        let plan: BaselinePlan = Baseline.plan(index: real.index, seed: 5)
        XCTAssertGreaterThanOrEqual(plan.activities.count, 12)
        XCTAssertLessThanOrEqual(plan.activities.count, 18)
        var orders: [Int] = []
        for a in plan.activities {
            guard let u = real.index.unit(id: a.unitId) else { XCTFail("unit"); continue }
            XCTAssertEqual(u.stage, .reception, "baseline stays inside Reception")
            XCTAssertFalse(ActivityGenerator.isGuessable(a), "\(a.key) would be a guess, not evidence")
            XCTAssertTrue(real.index.hasOwnSound(u))
            orders.append(u.order)
        }
        XCTAssertEqual(orders, orders.sorted())
        for (a, b) in zip(orders, orders.dropFirst()) { XCTAssertLessThanOrEqual(b - a, 6, "gaps between samples stay small: \(orders)") }
        XCTAssertGreaterThanOrEqual(orders.last ?? 0, 45, "the sample reaches the end of the Reception range")
        XCTAssertGreaterThanOrEqual(orders.first ?? 0, 3, "units 1 and 2 cannot give evidence")
        // The fixture has no Year 1 units; it still yields valid, non-guessable items.
        for a in Baseline.plan(index: fx.index, seed: 2).activities { XCTAssertFalse(ActivityGenerator.isGuessable(a)) }
    }

    func testBaselineIgnoresGuessableItemsWhenStoppingAndPlacing() throws {
        let single: Activity = try XCTUnwrap(generate(real, unit: "g-s", type: .listenChooseSound, seed: 1))
        XCTAssertTrue(ActivityGenerator.isGuessable(single))
        let guessed: BaselineItemResult = BaselineItemResult(activity: single, answer: Answer(correct: true, support: .independent))
        XCTAssertEqual(guessed.support, .modelled, "a one-choice item is recorded as help, never as knowledge")
        let miss: BaselineItemResult = BaselineItemResult(unitId: "g-t", correct: false)
        XCTAssertFalse(Baseline.shouldStop(results: [miss, guessed]))
        XCTAssertTrue(Baseline.shouldStop(results: [miss, guessed, miss]), "modelled items neither extend nor break a run of misses")
        // Placement ignores them: with only guessable evidence nothing is known, so the learner starts at the beginning.
        let p: BaselinePlacement = Progression.placeFromBaseline(index: real.index, results: [guessed], now: day(0))
        XCTAssertEqual(p.placementOrder, 1)
        XCTAssertTrue(p.provisionalSkills.isEmpty)
    }

    func testPlacementStepsBackThreeUnitsFromTheFirstMissAndIgnoresGuessesAbove() throws {
        let units: [GraphemeUnit] = real.index.units
        func correct(_ pos: Int) -> BaselineItemResult { return BaselineItemResult(unitId: units[pos].id, correct: true) }
        func wrong(_ pos: Int) -> BaselineItemResult { return BaselineItemResult(unitId: units[pos].id, correct: false) }
        // Known up to position 20, first miss at 30; lucky correct guesses at 35 and 45 must not move the placement up.
        let results: [BaselineItemResult] = [correct(3), correct(10), correct(20), wrong(30), correct(35), wrong(40), correct(45)]
        let p: BaselinePlacement = Progression.placeFromBaseline(index: real.index, results: results, now: day(0))
        XCTAssertEqual(p.placementUnitId, units[27].id, "three units before the first miss")
        for s in p.provisionalSkills {
            XCTAssertLessThan(real.index.unitOrder(id: s.unitId) ?? 999, p.placementOrder)
            XCTAssertEqual(s.status, .learning)
        }
        // Never below the first unit.
        let early: BaselinePlacement = Progression.placeFromBaseline(index: real.index, results: [wrong(1)], now: day(0))
        XCTAssertEqual(early.placementUnitId, units[0].id)
        let nearStart: BaselinePlacement = Progression.placeFromBaseline(index: real.index, results: [correct(3), wrong(4)], now: day(0))
        XCTAssertEqual(nearStart.placementUnitId, units[1].id)
        // No misses: the highest sampled unit (backed by the last three samples).
        let allRight: BaselinePlacement = Progression.placeFromBaseline(index: real.index, results: [correct(3), correct(6), correct(9)], now: day(0))
        XCTAssertEqual(allRight.placementUnitId, units[9].id)
    }

    func testLuckyGuessesAboveAGapNeverSkipUnknownUnits() {
        // A child who knows nothing past position 12 and guesses correctly on later samples is still placed 3 units before the first miss.
        let units: [GraphemeUnit] = real.index.units
        var results: [BaselineItemResult] = []
        for pos in stride(from: 3, to: 50, by: 3) {
            results.append(BaselineItemResult(unitId: units[pos].id, correct: pos <= 12 || pos % 2 == 0))
        }
        let firstMiss: Int = stride(from: 3, to: 50, by: 3).first(where: { !($0 <= 12 || $0 % 2 == 0) }) ?? 0
        let p: BaselinePlacement = Progression.placeFromBaseline(index: real.index, results: results, now: day(0))
        XCTAssertEqual(p.placementUnitId, units[max(0, firstMiss - Progression.baselineStepBackUnits)].id)
    }

    // MARK: M5 guessable first units

    func testOnlyUnitsOneAndTwoHaveFewChoiceRecognition() {
        for data in [fx, real] {
            let units: [GraphemeUnit] = data.index.units
            XCTAssertTrue(data.index.hasFewChoiceRecognition(unitId: units[0].id))
            XCTAssertTrue(data.index.hasFewChoiceRecognition(unitId: units[1].id))
            for u in units.dropFirst(2) { XCTAssertFalse(data.index.hasFewChoiceRecognition(unitId: u.id), u.id) }
        }
        for u in real.index.units.dropFirst(2) where real.index.hasOwnSound(u) {
            for type in [ActivityType.listenChooseSound, .findGrapheme] {
                guard let a = generate(real, unit: u.id, type: type, seed: 1) else { XCTFail("\(u.id) \(type)"); continue }
                XCTAssertGreaterThanOrEqual(ActivityGenerator.choiceCount(a) ?? 0, ActivityGenerator.minChoicesForEvidence, a.key)
                XCTAssertFalse(ActivityGenerator.isGuessable(a), a.key)
            }
        }
    }

    func testTwoChoiceItemsAreRecordedAsModelledNotIndependent() throws {
        for data in [fx, real] {
            let second: String = data.index.units[1].id
            let a: Activity = try XCTUnwrap(generate(data, unit: second, type: .listenChooseSound, seed: 3))
            XCTAssertEqual(ActivityGenerator.choiceCount(a), 2)
            XCTAssertFalse(ActivityGenerator.isSingleChoice(a))
            XCTAssertTrue(ActivityGenerator.isGuessable(a))
            XCTAssertEqual(ActivityGenerator.evidenceSupport(for: a, answered: .independent), .modelled)
            XCTAssertEqual(ActivityGenerator.evidenceSupport(for: a, answered: .prompted), .prompted)
            let third: Activity = try XCTUnwrap(generate(data, unit: data.index.units[2].id, type: .listenChooseSound, seed: 3))
            XCTAssertEqual(ActivityGenerator.evidenceSupport(for: third, answered: .independent), .independent)

            let snap: LearnerSnapshot = snapshotWithSecure(index: data.index, upTo: 1)
            let p: SessionPlan = SessionPlanner.plan(index: data.index, snapshot: snap, now: day(2), seed: 4, minutes: 7, focusUnitId: second)
            let guessable: [Activity] = p.activities.filter { ActivityGenerator.isGuessable($0) }
            XCTAssertFalse(guessable.isEmpty)
            for g in guessable { XCTAssertTrue(p.modelledKeys.contains(g.key), "\(g.key) would count as evidence") }
        }
    }

    func testUnitTwoDoesNotBlockTheSequenceOnceMet() {
        for data in [fx, real] {
            let idx: CurriculumIndex = data.index
            let second: GraphemeUnit = idx.units[1]
            var snap: LearnerSnapshot = snapshotWithSecure(index: idx, upTo: 1)
            XCTAssertEqual(Progression.nextUnit(index: idx, snapshot: snap, now: day(1))?.id, second.id, "not met yet")
            var met: SkillState = SkillState(unitId: second.id, track: .recognise)
            met = Mastery.update(skill: met, attempt: makeAttempt(unit: second.id, correct: true, support: .modelled), settings: MasterySettings(), now: day(0))
            snap.skills.append(met)
            XCTAssertEqual(Progression.nextUnit(index: idx, snapshot: snap, now: day(1))?.id, idx.units[2].id, "no deadlock at unit 2")
            // Met-only units are introductions, not "moving on gently".
            let e: UnitExplanation? = Progression.explainUnits(index: idx, snapshot: snap, now: day(1)).first(where: { $0.unitId == second.id })
            XCTAssertFalse((e?.reason ?? "").contains("Moving on gently"))
        }
    }

    // MARK: M4 p4-suffix

    func testSuffixUnitIsNotARecogniseUnitAndGatesOnBlending() throws {
        let idx: CurriculumIndex = real.index
        let suffix: GraphemeUnit = try XCTUnwrap(idx.unit(id: "p4-suffix"))
        XCTAssertTrue(CurriculumIndex.isInstructionAudio(suffix.audioId))
        XCTAssertFalse(idx.hasOwnSound(suffix))
        let tracks: [Track] = idx.applicableTracks(forUnit: suffix.id)
        XCTAssertFalse(tracks.contains(.recognise))
        XCTAssertTrue(tracks.contains(.blend))
        XCTAssertEqual(Progression.gateTracks(unit: suffix, index: idx), [.blend])
        let types: [ActivityType] = ActivityGenerator.supportedTypes(index: idx, unitId: suffix.id, knownOrder: suffix.order)
        for t in [ActivityType.listenChooseSound, .findGrapheme, .matchSoundGrapheme] { XCTAssertFalse(types.contains(t), "\(t)") }
        XCTAssertTrue(types.contains(.blendToWord))
        // Passing the blend gate is what unlocks whatever follows.
        var snap: LearnerSnapshot = snapshotWithSecure(index: idx, upTo: suffix.order - 1)
        XCTAssertEqual(Progression.nextUnit(index: idx, snapshot: snap, now: day(1))?.id, suffix.id)
        snap.skills.append(secureSkill(suffix.id, .blend))
        XCTAssertNotEqual(Progression.nextUnit(index: idx, snapshot: snap, now: day(1))?.id, suffix.id)
    }

    func testInstructionClipsAreNeverPlayedAsASound() {
        let idx: CurriculumIndex = real.index
        for seed in 0..<30 {
            for unit in ["p4-suffix", "p4-cvcc", "g-s"] {
                for type in [ActivityType.blendToWord, .listenChooseSound, .findGrapheme, .matchSoundGrapheme, .mixedReview] {
                    guard let a = generate(real, unit: unit, type: type, known: idx.maxOrder, seed: UInt64(seed)) else { continue }
                    XCTAssertFalse(a.audioIds.contains("i-blend"), a.key)
                    if case let .choose(choices, _, _) = a.payload {
                        for c in choices { XCTAssertFalse(CurriculumIndex.isInstructionAudio(c.audioId ?? ""), "\(a.key): \(c.id) plays an instruction clip") }
                        XCTAssertFalse(choices.contains { $0.id == "ed" }, "\(a.key): 'ed' has no sound clip to choose")
                    }
                }
            }
        }
        // A mixed review is never drawn from the suffix unit itself.
        for seed in 0..<40 {
            if let a = generate(real, unit: "p4-suffix", type: .mixedReview, seed: UInt64(seed)) { XCTAssertNotEqual(a.unitId, "p4-suffix") }
        }
    }

    // MARK: M2 homophones and ambiguous cloze

    func testWordHomophoneFieldsAreOptionalAndFlexible() throws {
        let plain: Word = try JSONDecoder().decode(Word.self, from: Data("{\"text\":\"cat\",\"graphemes\":[\"c\",\"a\",\"t\"]}".utf8))
        XCTAssertNil(plain.homophones)
        XCTAssertNil(plain.sameMeaningAs)
        let rich: Word = try JSONDecoder().decode(Word.self, from: Data(
            "{\"text\":\"sea\",\"graphemes\":[\"s\",\"ea\"],\"homophones\":[\"see\"],\"sameMeaningAs\":\"ocean\"}".utf8))
        XCTAssertEqual(rich.homophones, ["see"])
        XCTAssertEqual(rich.sameMeaningAs, ["ocean"], "a single string is accepted")
        let again: Word = try JSONDecoder().decode(Word.self, from: JSONEncoder().encode(rich))
        XCTAssertEqual(again, rich)
        // Bundled content (which may or may not carry the fields yet) keeps decoding.
        XCTAssertFalse(real.curriculum.words.isEmpty)
    }

    func testHomophoneTableAndContentFieldsBothCount() {
        let idx: CurriculumIndex = real.index
        for (a, b) in [("sea", "see"), ("be", "bee"), ("ate", "eight"), ("to", "too"), ("to", "two"), ("too", "two"), ("no", "know"), ("night", "knight")] {
            XCTAssertTrue(idx.areConfusable(a, b), "\(a)/\(b)")
            XCTAssertTrue(idx.areConfusable(b.uppercased(), a), "symmetric and case-insensitive")
        }
        XCTAssertFalse(idx.areConfusable("cat", "cut"))
        // Fields from the content are honoured too, in both directions.
        let base: Curriculum = fx.curriculum
        let words: [Word] = base.words.map { w -> Word in
            if w.text != "pit" { return w }
            return Word(text: w.text, graphemes: w.graphemes, emoji: w.emoji, pictureLabel: w.pictureLabel, concrete: w.concrete,
                        homophones: ["pat"], sameMeaningAs: ["hole"])
        }
        let c: Curriculum = Curriculum(schemaVersion: base.schemaVersion, contentVersion: base.contentVersion, units: base.units, words: words,
                                       trickyWords: base.trickyWords, sentences: base.sentences, stories: base.stories,
                                       wordRequirements: base.wordRequirements)
        let custom: CurriculumIndex = CurriculumIndex(c)
        XCTAssertTrue(custom.areConfusable("pit", "pat"))
        XCTAssertTrue(custom.areConfusable("pat", "pit"))
        XCTAssertTrue(custom.areConfusable("hole", "pit"))
    }

    func testChooseWordActivitiesNeverOfferAHomophoneOfTheAnswer() {
        let idx: CurriculumIndex = real.index
        var checked: Int = 0
        func assertClean(_ a: Activity, answer: String, choices: [Choice]) {
            for c in choices where !c.correct {
                checked += 1
                XCTAssertFalse(idx.areConfusable(answer, c.id), "\(a.key): '\(c.id)' clashes with '\(answer)'")
            }
        }
        for u in idx.units {
            for type in [ActivityType.blendToWord, .readPickPicture, .identifyTricky, .completeSentence] {
                for seed in 0..<3 {
                    guard let a = generate(real, unit: u.id, type: type, known: idx.maxOrder, seed: UInt64(seed)) else { continue }
                    switch a.payload {
                    case let .blend(_, word, choices, _): assertClean(a, answer: word, choices: choices)
                    case let .picture(word, choices): assertClean(a, answer: word, choices: choices)
                    case let .tricky(word, choices): assertClean(a, answer: word, choices: choices)
                    case let .sentence(_, _, choices, _): assertClean(a, answer: choices.first(where: { $0.correct })?.id ?? "", choices: choices)
                    default: break
                    }
                }
            }
        }
        // Targeted: the long-ee words include see and bee, whose partners sea and be are decodable by then.
        for seed in 0..<200 {
            guard let a = generate(real, unit: "g-ee", type: .blendToWord, known: idx.maxOrder, seed: UInt64(seed)),
                  case let .blend(_, word, choices, _) = a.payload else { continue }
            assertClean(a, answer: word, choices: choices)
        }
        XCTAssertGreaterThan(checked, 500)
    }

    func testBuildWordNeverAddsATileThatSpellsAHomophone() {
        let idx: CurriculumIndex = real.index
        for u in idx.units {
            for seed in 0..<4 {
                guard let a = generate(real, unit: u.id, type: .buildWord, known: idx.maxOrder, seed: UInt64(seed)),
                      case let .build(word, graphemes, tiles, _) = a.payload else { continue }
                var extras: [String] = tiles
                for g in graphemes { if let i = extras.firstIndex(of: g) { extras.remove(at: i) } }
                for tile in extras {
                    for i in 0..<graphemes.count {
                        var swapped: [String] = graphemes
                        swapped[i] = tile
                        if let text = GraphemeText.join(swapped) {
                            XCTAssertFalse(idx.areConfusable(word, text), "\(a.key): extra tile '\(tile)' spells '\(text)'")
                        }
                    }
                }
            }
        }
    }

    func testClozeNeedsAPictureAndNeverOffersAMinimalPair() {
        let idx: CurriculumIndex = real.index
        var generated: Int = 0
        var offeredAny: Int = 0
        for u in idx.units {
            guard ActivityGenerator.supportedTypes(index: idx, unitId: u.id, knownOrder: u.order).contains(.completeSentence) else { continue }
            for known in [u.order, idx.maxOrder] {
                for seed in 0..<6 {
                    guard let a = generate(real, unit: u.id, type: .completeSentence, known: known, seed: UInt64(seed)) else {
                        XCTFail("\(u.id) seed \(seed): supported but nil"); continue
                    }
                    guard case let .sentence(_, _, choices, emoji) = a.payload else { XCTFail("payload"); continue }
                    generated += 1
                    XCTAssertFalse((emoji ?? "").isEmpty, "\(a.key): a cloze needs a picture")
                    let parts: [String] = a.key.components(separatedBy: "|")
                    guard parts.count >= 4, let sentence = idx.sentence(id: parts[2]), let blank = Int(parts[3]),
                          case let .word(text, tokenGraphemes) = sentence.tokens[blank] else { XCTFail("key \(a.key)"); continue }
                    let graphemes: [String] = idx.word(text: text)?.graphemes ?? tokenGraphemes
                    XCTAssertNotNil(idx.picture(forSentence: sentence), a.key)
                    for c in choices where !c.correct {
                        offeredAny += 1
                        guard let w = idx.word(text: c.id.lowercased()) else { XCTFail("\(a.key): \(c.id) is not a word"); continue }
                        XCTAssertGreaterThanOrEqual(ActivityGenerator.graphemeDistance(graphemes, w.graphemes), 2,
                                                    "\(a.key): '\(c.id)' is a one-grapheme minimal pair of '\(text)'")
                        XCTAssertFalse(idx.areConfusable(text, c.id), a.key)
                    }
                }
            }
        }
        XCTAssertGreaterThan(generated, 20)
        XCTAssertGreaterThan(offeredAny, 20)
    }

    func testGraphemeDistanceIsEditDistanceOverGraphemes() {
        XCTAssertEqual(ActivityGenerator.graphemeDistance(["m", "o", "p"], ["m", "a", "p"]), 1)
        XCTAssertEqual(ActivityGenerator.graphemeDistance(["m", "o", "p"], ["t", "o", "p"]), 1)
        XCTAssertEqual(ActivityGenerator.graphemeDistance(["c", "a", "t"], ["c", "a", "r", "t"]), 1)
        XCTAssertEqual(ActivityGenerator.graphemeDistance(["m", "o", "p"], ["t", "i", "p"]), 2)
        XCTAssertEqual(ActivityGenerator.graphemeDistance([], ["a", "b"]), 2)
        XCTAssertEqual(ActivityGenerator.graphemeDistance(["a"], ["a"]), 0)
    }

    func testSentencePicturesComeFromTheSentenceOrItsSingleSentenceStoryPage() throws {
        // Fixture: s-1 has no emoji of its own but story-1 shows it alone on a page with a picture; s-3 has its own.
        let s1: Sentence = try XCTUnwrap(fx.index.sentence(id: "s-1"))
        let s3: Sentence = try XCTUnwrap(fx.index.sentence(id: "s-3"))
        let s5: Sentence = try XCTUnwrap(fx.index.sentence(id: "s-5"))
        XCTAssertEqual(fx.index.picture(forSentence: s1), "🥫")
        XCTAssertEqual(fx.index.picture(forSentence: s3), "🥫")
        XCTAssertNil(fx.index.picture(forSentence: s5), "no picture anywhere, so it can never be a cloze")
        for u in fx.index.units {
            for seed in 0..<8 {
                guard let a = generate(fx, unit: u.id, type: .completeSentence, seed: UInt64(seed)) else { continue }
                XCTAssertFalse(a.key.contains("|s-5|"), "unpictured sentence used: \(a.key)")
            }
        }
    }
}
