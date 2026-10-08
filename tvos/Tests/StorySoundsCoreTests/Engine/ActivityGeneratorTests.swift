import XCTest
@testable import StorySoundsCore

final class ActivityGeneratorTests: XCTestCase {
    private var fx: RealData { return TestData.fixture }
    private var real: RealData { return TestData.real }

    private func generate(_ data: RealData, unit: String, type: ActivityType, known: Int? = nil, seed: UInt64,
                          choices: Int = 3, exclude: Set<String> = []) -> Activity? {
        var rng: SeededRNG = SeededRNG(seed: seed)
        let order: Int = known ?? (data.index.unitOrder(id: unit) ?? 0)
        let spec: ActivitySpec = ActivitySpec(unitId: unit, type: type, knownOrder: order, choiceCount: choices, excludeKeys: exclude)
        return ActivityGenerator.generate(curriculum: data.curriculum, index: data.index, spec: spec, rng: &rng)
    }

    private func sweep(_ data: RealData, units: [GraphemeUnit], seeds: Range<Int>, extraKnown: Int) {
        for u in units {
            let known: Int = min(data.index.maxOrder, u.order + extraKnown)
            let supported: [ActivityType] = ActivityGenerator.supportedTypes(index: data.index, unitId: u.id, knownOrder: known)
            for type in supported {
                for seed in seeds {
                    guard let a = generate(data, unit: u.id, type: type, known: known, seed: UInt64(seed)) else {
                        XCTFail("\(u.id) \(type) seed \(seed): supported but nil")
                        continue
                    }
                    let spec: ActivitySpec = ActivitySpec(unitId: u.id, type: type, knownOrder: known)
                    validateActivity(a, spec: spec, index: data.index)
                }
            }
        }
    }

    // MARK: Property-style sweeps

    func testFixtureEveryUnitEverySupportedTypeManySeeds() {
        sweep(fx, units: fx.index.units, seeds: 0..<30, extraKnown: 0)
        sweep(fx, units: fx.index.units, seeds: 0..<10, extraKnown: 3)
    }

    func testRealEveryUnitEverySupportedTypeAtItsOwnOrder() {
        sweep(real, units: real.index.units, seeds: 0..<4, extraKnown: 0)
    }

    func testRealEveryUnitWithMoreKnownContent() {
        sweep(real, units: real.index.units, seeds: 0..<2, extraKnown: 12)
    }

    func testRealSampledUnitsManySeeds() {
        var sampled: [GraphemeUnit] = []
        for (i, u) in real.index.units.enumerated() where i % 9 == 0 { sampled.append(u) }
        sweep(real, units: sampled, seeds: 4..<24, extraKnown: 0)
    }

    func testEveryApplicableTrackHasAPlayableType() {
        for u in real.index.units {
            let supported: [ActivityType] = ActivityGenerator.supportedTypes(index: real.index, unitId: u.id, knownOrder: u.order)
            for t in real.index.applicableTracks(forUnit: u.id) {
                XCTAssertTrue(ActivityGenerator.coreTypes(for: t).contains(where: { supported.contains($0) }), "\(u.id) \(t)")
            }
        }
    }

    // MARK: Support

    func testSupportedTypesReflectTaughtContent() {
        let s: [ActivityType] = ActivityGenerator.supportedTypes(index: real.index, unitId: "g-s", knownOrder: 1)
        XCTAssertTrue(s.contains(.listenChooseSound))
        XCTAssertTrue(s.contains(.matchSoundGrapheme))
        XCTAssertTrue(s.contains(.findGrapheme))
        XCTAssertTrue(s.contains(.identifyTricky))
        XCTAssertTrue(s.contains(.mixedReview))
        XCTAssertFalse(s.contains(.blendToWord), "no decodable word exists yet")
        XCTAssertFalse(s.contains(.completeSentence))
        XCTAssertFalse(s.contains(.readStory))
        XCTAssertNil(generate(real, unit: "g-s", type: .blendToWord, seed: 1))
        XCTAssertNil(generate(real, unit: "g-s", type: .readStory, seed: 1))
        XCTAssertNil(generate(real, unit: "does-not-exist", type: .listenChooseSound, known: 5, seed: 1))
        let later: [ActivityType] = ActivityGenerator.supportedTypes(index: real.index, unitId: "g-oa", knownOrder: real.index.unitOrder(id: "g-oa") ?? 40)
        XCTAssertTrue(later.contains(.blendToWord))
        XCTAssertTrue(later.contains(.readStory))
        XCTAssertTrue(later.contains(.completeSentence))
        XCTAssertTrue(later.contains(.fluency))
    }

    func testConsolidationUnitsHaveNoRecogniseActivities() {
        let types: [ActivityType] = ActivityGenerator.supportedTypes(index: real.index, unitId: "p4-cvcc", knownOrder: 51)
        XCTAssertFalse(types.contains(.listenChooseSound))
        XCTAssertFalse(types.contains(.matchSoundGrapheme))
        XCTAssertTrue(types.contains(.blendToWord))
    }

    func testKnownOrderIsRaisedToIncludeTheTargetUnit() {
        guard let a = generate(real, unit: "g-t", type: .listenChooseSound, known: 1, seed: 2) else { return XCTFail("nil") }
        XCTAssertTrue(a.graphemesUsed.contains("t"))
        validateActivity(a, spec: ActivitySpec(unitId: "g-t", type: .listenChooseSound, knownOrder: 1), index: real.index)
    }

    // MARK: Determinism and variety

    func testEqualSeedsGiveEqualActivities() {
        for data in [fx, real] {
            for u in data.index.units where u.order % 5 == 1 {
                for type in ActivityGenerator.supportedTypes(index: data.index, unitId: u.id, knownOrder: u.order) {
                    let a: Activity? = generate(data, unit: u.id, type: type, seed: 77)
                    let b: Activity? = generate(data, unit: u.id, type: type, seed: 77)
                    XCTAssertEqual(a, b, "\(u.id) \(type)")
                }
            }
        }
    }

    func testDifferentSeedsGiveVariety() {
        var keys: Set<String> = []
        var shuffles: Set<String> = []
        for seed in 0..<30 {
            if let a = generate(real, unit: "g-b", type: .blendToWord, seed: UInt64(seed)) { keys.insert(a.key) }
            if let a = generate(real, unit: "g-b", type: .buildWord, seed: UInt64(seed)), case let .build(_, _, tiles, _) = a.payload {
                shuffles.insert(tiles.joined(separator: "."))
            }
        }
        XCTAssertGreaterThan(keys.count, 3)
        XCTAssertGreaterThan(shuffles.count, 3)
    }

    func testExcludeKeysPreferFreshItemsButNeverRunDry() throws {
        let first: Activity = try XCTUnwrap(generate(fx, unit: "g-i", type: .blendToWord, seed: 1))
        for seed in 0..<12 {
            let next: Activity = try XCTUnwrap(generate(fx, unit: "g-i", type: .blendToWord, seed: UInt64(seed), exclude: [first.key]))
            XCTAssertNotEqual(next.key, first.key)
        }
        // Exclude everything: it still produces something rather than failing.
        var all: Set<String> = []
        for seed in 0..<60 { if let a = generate(fx, unit: "g-i", type: .blendToWord, seed: UInt64(seed)) { all.insert(a.key) } }
        XCTAssertNotNil(generate(fx, unit: "g-i", type: .blendToWord, seed: 5, exclude: all))
    }

    func testChoiceCountIsHonouredAndClamped() throws {
        for count in [2, 3, 4] {
            let a: Activity = try XCTUnwrap(generate(real, unit: "g-ee", type: .listenChooseSound, seed: 3, choices: count))
            guard case let .choose(choices, _, _) = a.payload else { return XCTFail("payload") }
            XCTAssertEqual(choices.count, count)
        }
        // Only one sound is taught at order 1, so there is nothing to distract with.
        let first: Activity = try XCTUnwrap(generate(real, unit: "g-s", type: .listenChooseSound, seed: 3))
        guard case let .choose(choices, target, _) = first.payload else { return XCTFail("payload") }
        XCTAssertEqual(choices.count, 1)
        XCTAssertEqual(target, "s")
        XCTAssertTrue(choices[0].correct)
        // Such an item cannot be answered wrongly, so it must never be recorded as independent evidence.
        XCTAssertTrue(ActivityGenerator.isSingleChoice(first))
        XCTAssertEqual(ActivityGenerator.evidenceSupport(for: first, answered: .independent), .modelled)
        XCTAssertEqual(ActivityGenerator.evidenceSupport(for: first, answered: .prompted), .prompted)
    }

    // MARK: Distractor rules

    func testDistractorsNeverSoundLikeTheTarget() {
        for seed in 0..<40 {
            if let a = generate(fx, unit: "g-a-ai", type: .listenChooseSound, known: 9, seed: UInt64(seed)), case let .choose(choices, target, _) = a.payload {
                XCTAssertEqual(target, "a")
                XCTAssertFalse(choices.contains { $0.id == "ai" }, "ai also says /ai/")
            } else { XCTFail("nil") }
            if let a = generate(fx, unit: "g-ai", type: .findGrapheme, known: 9, seed: UInt64(seed)), case let .choose(choices, _, _) = a.payload {
                XCTAssertFalse(choices.contains { $0.id == "a" }, "a also says /ai/ once g-a-ai is taught")
            } else { XCTFail("nil") }
            if let a = generate(fx, unit: "g-a", type: .matchSoundGrapheme, known: 9, seed: UInt64(seed)), case let .choose(choices, _, _) = a.payload {
                XCTAssertFalse(choices.contains { $0.id == "g-a-ai" }, "a really does say /ai/ too")
            } else { XCTFail("nil") }
        }
    }

    func testMisconceptionsArePreferredWhenTaughtAndIgnoredWhenNot() {
        for seed in 0..<30 {
            if let a = generate(fx, unit: "g-i", type: .listenChooseSound, seed: UInt64(seed), choices: 2), case let .choose(choices, _, _) = a.payload {
                XCTAssertEqual(Set(choices.map { $0.id }), ["i", "a"], "the taught confusable letter should be the distractor")
            } else { XCTFail("nil") }
            // Misconceptions m (for n) and z (for s) are not taught yet: they must never appear.
            if let a = generate(fx, unit: "g-n", type: .findGrapheme, seed: UInt64(seed)), case let .choose(choices, _, _) = a.payload {
                XCTAssertFalse(choices.contains { $0.id == "m" })
            }
            if let a = generate(fx, unit: "g-s", type: .mixedReview, seed: UInt64(seed)), case let .choose(choices, _, _) = a.payload {
                XCTAssertFalse(choices.contains { $0.id == "z" })
            }
        }
    }

    func testTrickyWordsOnlyAfterIntroduction() {
        for seed in 0..<30 {
            guard let a = generate(fx, unit: "g-s", type: .identifyTricky, seed: UInt64(seed)) else { return XCTFail("nil") }
            XCTAssertFalse(a.trickyUsed.contains("said"))
            guard case let .tricky(word, choices) = a.payload else { return XCTFail("payload") }
            XCTAssertTrue(["the", "is"].contains(word))
            XCTAssertEqual(Set(choices.map { $0.id }), ["the", "is"])
        }
        var sawSaid: Bool = false
        for seed in 0..<30 {
            if let a = generate(fx, unit: "g-ai", type: .identifyTricky, seed: UInt64(seed)), a.trickyUsed.contains("said") { sawSaid = true }
        }
        XCTAssertTrue(sawSaid)
    }

    func testSentencesNeverBlankOrShowUnintroducedTrickyWords() {
        for u in real.index.units {
            guard ActivityGenerator.supportedTypes(index: real.index, unitId: u.id, knownOrder: u.order).contains(.completeSentence) else { continue }
            for seed in 0..<3 {
                guard let a = generate(real, unit: u.id, type: .completeSentence, seed: UInt64(seed)) else { XCTFail("nil"); continue }
                guard case let .sentence(tokens, blank, choices, _) = a.payload else { XCTFail("payload"); continue }
                XCTAssertEqual(tokens.filter { $0 == "___" }.count, 1)
                XCTAssertEqual(choices.filter { $0.correct }.count, 1)
                XCTAssertTrue(blank < tokens.count)
            }
        }
    }

    // MARK: Tiles, split digraphs

    func testSplitDigraphWordsAreBuiltFromSplitTiles() {
        var sawSplit: Bool = false
        for seed in 0..<25 {
            guard let a = generate(real, unit: "g-split-a", type: .buildWord, seed: UInt64(seed)) else { return XCTFail("nil") }
            guard case let .build(word, graphemes, tiles, _) = a.payload else { return XCTFail("payload") }
            if graphemes.contains("a_e") {
                sawSplit = true
                XCTAssertTrue(tiles.contains("a_e"))
                XCTAssertEqual(GraphemeText.join(graphemes), word)
            }
        }
        XCTAssertTrue(sawSplit)
    }

    func testSegmentTilesIncludeLetterSplitsOfDigraphsOnlyWhenTaught() {
        for seed in 0..<40 {
            guard let a = generate(fx, unit: "g-sh", type: .segmentWord, seed: UInt64(seed)) else { return XCTFail("nil") }
            guard case let .segment(word, graphemes, tiles, _) = a.payload else { return XCTFail("payload") }
            XCTAssertEqual(word, "ship")
            XCTAssertEqual(graphemes, ["sh", "i", "p"])
            // "h" is not taught in the fixture, so the pieces s + h must not both be offered.
            XCTAssertFalse(tiles.contains("h"))
        }
        // In the real curriculum both s and h are taught before sh, so the pieces appear as tempting extra tiles.
        var sawPieces: Bool = false
        for seed in 0..<40 {
            if let a = generate(real, unit: "g-sh", type: .segmentWord, seed: UInt64(seed)), case let .segment(_, graphemes, tiles, _) = a.payload,
               graphemes.contains("sh"), tiles.contains("s"), tiles.contains("h") { sawPieces = true }
        }
        XCTAssertTrue(sawPieces)
    }

    // MARK: Mixed review, stories, fluency

    func testMixedReviewDrawsOnSeveralTaughtUnits() {
        var units: Set<String> = []
        for seed in 0..<40 {
            guard let a = generate(real, unit: "g-oa", type: .mixedReview, seed: UInt64(seed)) else { return XCTFail("nil") }
            units.insert(a.unitId)
            XCTAssertLessThanOrEqual(real.index.unitOrder(id: a.unitId) ?? 999, real.index.unitOrder(id: "g-oa") ?? 0)
        }
        XCTAssertGreaterThan(units.count, 5)
    }

    func testStoryAndFluencyContent() throws {
        let story: Activity = try XCTUnwrap(generate(real, unit: "g-oa", type: .readStory, seed: 1))
        guard case let .story(title, pages, questions) = story.payload else { return XCTFail("payload") }
        XCTAssertFalse(title.isEmpty)
        XCTAssertGreaterThanOrEqual(pages.count, 2)
        XCTAssertFalse(questions.isEmpty)
        let fluency: Activity = try XCTUnwrap(generate(real, unit: "g-oa", type: .fluency, seed: 1))
        guard case let .fluency(words, target) = fluency.payload else { return XCTFail("payload") }
        XCTAssertGreaterThanOrEqual(words.count, 3)
        XCTAssertGreaterThan(target, 0)
    }

    // MARK: Simplify and model

    func testSimplifyKeepsOneCorrectChoiceAndFewerOptions() {
        for u in fx.index.units {
            for type in ActivityGenerator.supportedTypes(index: fx.index, unitId: u.id, knownOrder: u.order) {
                guard let a = generate(fx, unit: u.id, type: type, seed: 4, choices: 4) else { XCTFail("nil"); continue }
                let easy: Activity = ActivityGenerator.simplify(a)
                XCTAssertTrue(easy.key.hasSuffix("~easy"))
                XCTAssertEqual(ActivityGenerator.simplify(easy).key, easy.key, "simplify is idempotent on the key")
                XCTAssertEqual(easy.type, a.type)
                XCTAssertEqual(easy.unitId, a.unitId)
                func check(_ before: [Choice], _ after: [Choice]) {
                    XCTAssertLessThanOrEqual(after.count, max(2, 0))
                    XCTAssertLessThanOrEqual(after.count, before.count)
                    XCTAssertEqual(after.filter { $0.correct }.count, 1)
                }
                switch (a.payload, easy.payload) {
                case let (.choose(b, _, _), .choose(c, _, _)): check(b, c)
                case let (.blend(_, _, b, _), .blend(_, _, c, _)): check(b, c)
                case let (.picture(_, b), .picture(_, c)): check(b, c)
                case let (.tricky(_, b), .tricky(_, c)): check(b, c)
                case let (.sentence(_, _, b, _), .sentence(_, _, c, _)): check(b, c)
                case let (.segment(_, g, _, _), .segment(_, _, tiles, _)): XCTAssertEqual(tiles.sorted(), g.sorted())
                case let (.build(_, g, _, _), .build(_, _, tiles, _)): XCTAssertEqual(tiles.sorted(), g.sorted())
                case let (.story(_, _, qb), .story(_, _, qa)):
                    for (x, y) in zip(qb, qa) { check(x.choices, y.choices) }
                case let (.fluency(wb, _), .fluency(wa, _)): XCTAssertLessThanOrEqual(wa.count, wb.count)
                default: break
                }
            }
        }
    }

    func testModelledStepsExistForEveryTypeAndUseWarmLanguage() {
        for u in real.index.units where u.order % 6 == 1 {
            for type in ActivityGenerator.supportedTypes(index: real.index, unitId: u.id, knownOrder: u.order) {
                guard let a = generate(real, unit: u.id, type: type, seed: 9) else { XCTFail("nil"); continue }
                let steps: [String] = ActivityGenerator.modelledSteps(a)
                XCTAssertGreaterThanOrEqual(steps.count, 2, a.key)
                for s in steps {
                    XCTAssertFalse(s.isEmpty)
                    for t in templateTokens(s, content: a) { XCTAssertFalse(Feedback.bannedWords.contains(t), "\(a.key): '\(t)' in '\(s)'") }
                }
            }
        }
    }
}
