import XCTest
@testable import StorySoundsCore

final class CurriculumIndexTests: XCTestCase {
    private var fx: CurriculumIndex { return TestData.fixture.index }
    private var real: CurriculumIndex { return TestData.real.index }

    // MARK: Fixture

    func testTaughtGraphemesGrowWithOrderAndSkipConsolidation() {
        XCTAssertTrue(fx.taughtGraphemes(upToOrder: 0).isEmpty)
        XCTAssertEqual(fx.taughtGraphemes(upToOrder: 1), ["s"])
        XCTAssertEqual(fx.taughtGraphemes(upToOrder: 5), ["s", "a", "t", "p", "i"])
        XCTAssertEqual(fx.taughtGraphemeList(upToOrder: 3), ["s", "a", "t"])
        XCTAssertTrue(fx.taughtGraphemes(upToOrder: 7).contains("sh"))
        // The consolidation unit lists clusters that are NOT new graphemes.
        XCTAssertFalse(fx.taughtGraphemes(upToOrder: 10).contains("st"))
        XCTAssertFalse(fx.taughtGraphemes(upToOrder: 10).contains("nd"))
        XCTAssertEqual(fx.taughtGraphemes(upToOrder: 999), fx.taughtGraphemes(upToOrder: 10))
    }

    func testWordDecodabilityNeedsGraphemesAndRequirements() throws {
        let ship: Word = try XCTUnwrap(fx.word(text: "ship"))
        XCTAssertFalse(fx.isWordDecodable(ship, atOrder: 6))
        XCTAssertTrue(fx.isWordDecodable(ship, atOrder: 7))

        // "spa" only uses taught letters from order 4, but its requirement (g-a-ai, order 9) gates it.
        let spa: Word = try XCTUnwrap(fx.word(text: "spa"))
        XCTAssertFalse(fx.isWordDecodable(spa, atOrder: 8))
        XCTAssertTrue(fx.isWordDecodable(spa, atOrder: 9))
        XCTAssertEqual(fx.unlockOrder(forWord: spa), 9)

        let tint: Word = try XCTUnwrap(fx.word(text: "tint"))
        XCTAssertFalse(fx.isWordDecodable(tint, atOrder: 9))
        XCTAssertTrue(fx.isWordDecodable(tint, atOrder: 10))
    }

    func testDecodableWordsAreExactlyTheDecodableOnes() {
        for n in 0...10 {
            let listed: Set<String> = Set(fx.decodableWords(atOrder: n).map { $0.text })
            var expected: Set<String> = []
            for w in TestData.fixture.curriculum.words where fx.isWordDecodable(w, atOrder: n) { expected.insert(w.text) }
            XCTAssertEqual(listed, expected, "order \(n)")
        }
    }

    func testSentenceUnlockUsesTokensEvenWhenStoredValueIsTooLow() throws {
        let s5: Sentence = try XCTUnwrap(fx.sentence(id: "s-5"))
        XCTAssertEqual(s5.unlockedByOrder, 2)
        XCTAssertEqual(fx.unlockOrder(forSentence: s5), 7)
        XCTAssertFalse(fx.decodableSentences(atOrder: 6).contains { $0.id == "s-5" })
        XCTAssertTrue(fx.decodableSentences(atOrder: 7).contains { $0.id == "s-5" })
        // Tricky tokens are gated by their introduction order.
        let s3: Sentence = try XCTUnwrap(fx.sentence(id: "s-3"))
        XCTAssertEqual(fx.unlockOrder(forSentence: s3), 6)
    }

    func testStoriesUnlockWithTheirLatestSentence() {
        XCTAssertEqual(fx.decodableStories(atOrder: 5).map { $0.id }, ["story-1"])
        XCTAssertEqual(Set(fx.decodableStories(atOrder: 7).map { $0.id }), ["story-1", "story-2"])
        XCTAssertTrue(fx.decodableStories(atOrder: 4).isEmpty)
    }

    func testTrickyIntroduction() {
        XCTAssertTrue(fx.isTrickyIntroduced("The", atOrder: 1))
        XCTAssertFalse(fx.isTrickyIntroduced("said", atOrder: 7))
        XCTAssertTrue(fx.isTrickyIntroduced("said", atOrder: 8))
        XCTAssertFalse(fx.isTrickyIntroduced("unknown", atOrder: 99))
        XCTAssertEqual(fx.trickyWords(introducedByOrder: 1).count, 2)
    }

    func testSoundSharingFindsOtherSpellingsOnlyOnceTaught() throws {
        let ai: GraphemeUnit = try XCTUnwrap(fx.unit(id: "g-ai"))
        XCTAssertEqual(fx.graphemesSharingSound(with: ai, atOrder: 8), ["ai"])
        XCTAssertEqual(fx.graphemesSharingSound(with: ai, atOrder: 9), ["ai", "a"])
    }

    func testPhonemeKeysTreatSameSoundsAsOne() {
        XCTAssertEqual(CurriculumIndex.parsePhonemeKeys("/oo/ (long)"), ["oo"])
        XCTAssertEqual(CurriculumIndex.parsePhonemeKeys("/oo/ or /yoo/"), ["oo", "yoo"])
        XCTAssertFalse(CurriculumIndex.parsePhonemeKeys("/oo/ (long)").isDisjoint(with: CurriculumIndex.parsePhonemeKeys("/oo/ or /yoo/")))
        XCTAssertEqual(CurriculumIndex.parsePhonemeKeys("/er/"), CurriculumIndex.parsePhonemeKeys("/ur/"))
    }

    func testApplicableTracksInFixture() {
        XCTAssertEqual(fx.applicableTracks(forUnit: "g-s"), [.recognise, .read])
        XCTAssertEqual(fx.applicableTracks(forUnit: "g-a"), [.recognise])
        XCTAssertTrue(fx.applicableTracks(forUnit: "g-t").contains(.blend))
        XCTAssertFalse(fx.applicableTracks(forUnit: "p4-cvcc").contains(.recognise))
    }

    func testGraphemeJoinHandlesSplitDigraphs() {
        XCTAssertEqual(GraphemeText.join(["c", "a_e", "k"]), "cake")
        XCTAssertEqual(GraphemeText.join(["s", "l", "i_e", "d"]), "slide")
        XCTAssertEqual(GraphemeText.join(["sh", "a_e", "k"]), "shake")
        XCTAssertEqual(GraphemeText.join(["a_e", "g"]), "age")
        XCTAssertNil(GraphemeText.join(["c", "a_e"]))
        XCTAssertTrue(GraphemeText.isSplit("a_e"))
        XCTAssertFalse(GraphemeText.isSplit("ae"))
    }

    // MARK: Real data

    func testRealWordsAllJoinAndAreEventuallyDecodable() {
        let c: Curriculum = TestData.real.curriculum
        for w in c.words {
            XCTAssertEqual(GraphemeText.join(w.graphemes), w.text.lowercased(), "word \(w.text)")
            XCTAssertLessThan(real.unlockOrder(forWord: w), Int.max, "word \(w.text) uses an untaught grapheme")
            XCTAssertLessThanOrEqual(real.unlockOrder(forWord: w), real.maxOrder)
        }
        XCTAssertEqual(real.decodableWords(atOrder: real.maxOrder).count, Set(c.words.map { $0.text.lowercased() }).count)
    }

    func testRealSentencesAndStoriesAreGated() {
        let c: Curriculum = TestData.real.curriculum
        for s in c.sentences {
            let unlock: Int = real.unlockOrder(forSentence: s)
            XCTAssertLessThanOrEqual(unlock, real.maxOrder, s.id)
            if let stored = s.unlockedByOrder { XCTAssertGreaterThanOrEqual(unlock, stored, s.id) }
        }
        for st in c.stories { XCTAssertLessThanOrEqual(real.unlockOrder(forStory: st), real.maxOrder, st.id) }
        XCTAssertFalse(real.decodableStories(atOrder: real.maxOrder).isEmpty)
    }

    func testRealWordRequirementsGateWords() {
        let c: Curriculum = TestData.real.curriculum
        var checked: Int = 0
        for (text, reqs) in c.wordRequirements.sorted(by: { $0.key < $1.key }) {
            guard let w = real.word(text: text) else { continue }
            for r in reqs {
                guard let o = real.unitOrder(id: r) else { XCTFail("unknown unit \(r)"); continue }
                XCTAssertGreaterThanOrEqual(real.unlockOrder(forWord: w), o, text)
                XCTAssertFalse(real.isWordDecodable(w, atOrder: o - 1), "\(text) should not be decodable before \(r)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 100)
    }

    func testRealApplicableTracks() {
        for u in real.units {
            let tracks: [Track] = real.applicableTracks(forUnit: u.id)
            XCTAssertFalse(tracks.isEmpty, "\(u.id) has nothing to practise")
            if real.isConsolidation(u) { XCTAssertFalse(tracks.contains(.recognise), u.id) } else { XCTAssertTrue(tracks.contains(.recognise), u.id) }
        }
        XCTAssertEqual(real.units.first?.id, "g-s")
    }
}
