import XCTest
@testable import StorySoundsCore

final class FeedbackTests: XCTestCase {
    private var real: RealData { return TestData.real }

    private func allAnswers() -> [Answer] {
        var out: [Answer] = []
        for correct in [true, false] {
            for support in [SupportLevel.independent, SupportLevel.prompted, SupportLevel.modelled] {
                out.append(Answer(correct: correct, support: support, responseMs: 1200))
            }
        }
        return out
    }

    private func activities(units: Set<String>? = nil, stride: Int = 1) -> [Activity] {
        var out: [Activity] = []
        for (i, u) in real.index.units.enumerated() where i % stride == 0 {
            if let only = units, !only.contains(u.id) { continue }
            for type in ActivityGenerator.supportedTypes(index: real.index, unitId: u.id, knownOrder: u.order) {
                var rng: SeededRNG = SeededRNG(seed: UInt64(i) &+ 5)
                let spec: ActivitySpec = ActivitySpec(unitId: u.id, type: type, knownOrder: u.order)
                if let a = ActivityGenerator.generate(curriculum: real.curriculum, index: real.index, spec: spec, rng: &rng) { out.append(a) }
            }
        }
        return out
    }

    func testNoFailureLanguageInAnyFeedbackForAnyActivityOrAnswer() {
        var checked: Int = 0
        for a in activities() {
            for ans in allAnswers() {
                let text: String = Feedback.text(for: a, answer: ans)
                XCTAssertFalse(text.isEmpty, a.key)
                for t in tokens(of: text) {
                    XCTAssertFalse(Feedback.bannedWords.contains(t), "'\(t)' in feedback '\(text)' for \(a.key)")
                }
                let lower: String = text.lowercased()
                for phrase in ["try again", "not right", "not correct", "no!", "oops"] {
                    XCTAssertFalse(lower.contains(phrase), "'\(phrase)' in '\(text)'")
                }
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 1000)
        for s in Feedback.staticPhrases() {
            for t in tokens(of: s) { XCTAssertFalse(Feedback.bannedWords.contains(t), s) }
        }
    }

    func testNarrationAndPromptsAreFreeOfFailureLanguageToo() {
        for a in activities(stride: 3) {
            for t in templateTokens(a.prompt, content: a) { XCTAssertFalse(Feedback.bannedWords.contains(t), "\(a.key): \(a.prompt)") }
            for t in tokens(of: a.spokenPrompt) { XCTAssertFalse(Feedback.bannedWords.contains(t), "\(a.key): \(a.spokenPrompt)") }
            for step in ActivityGenerator.modelledSteps(a) {
                for t in templateTokens(step, content: a) { XCTAssertFalse(Feedback.bannedWords.contains(t), "\(a.key): \(step)") }
            }
            for step in ActivityGenerator.modelledSteps(ActivityGenerator.simplify(a)) {
                for t in templateTokens(step, content: a) { XCTAssertFalse(Feedback.bannedWords.contains(t), "\(a.key): \(step)") }
            }
        }
    }

    func testDecodableWordsThatLookLikeFailureWordsAreNotEchoed() {
        // "bad" and "wrong" are ordinary decodable words; they must never be spoken back inside a reaction.
        for word in ["bad", "wrong", "fail"] {
            let a: Activity = Activity(key: "blendToWord|x|\(word)", type: .blendToWord, unitId: "g-b", track: .blend, prompt: "p", spokenPrompt: "s",
                                       audioIds: [], payload: .blend(graphemes: ["b", "a", "d"], word: word, choices: [], emoji: nil),
                                       graphemesUsed: [], trickyUsed: [])
            for ans in allAnswers() {
                for t in tokens(of: Feedback.text(for: a, answer: ans)) { XCTAssertFalse(Feedback.bannedWords.contains(t), word) }
            }
        }
    }

    func testFeedbackRelatesToTheActionAndIsDeterministic() throws {
        var rng: SeededRNG = SeededRNG(seed: 1)
        let spec: ActivitySpec = ActivitySpec(unitId: "g-s", type: .listenChooseSound, knownOrder: 1)
        let a: Activity = try XCTUnwrap(ActivityGenerator.generate(curriculum: real.curriculum, index: real.index, spec: spec, rng: &rng))
        let good: String = Feedback.text(for: a, answer: Answer(correct: true, support: .independent))
        XCTAssertTrue(good.contains("sound for s"), good)
        XCTAssertEqual(good, Feedback.text(for: a, answer: Answer(correct: true, support: .independent)))
        let help: String = Feedback.text(for: a, answer: Answer(correct: false, support: .independent))
        XCTAssertTrue(help.contains("Let's"), help)
        let together: String = Feedback.text(for: a, answer: Answer(correct: true, support: .modelled))
        XCTAssertTrue(together.lowercased().contains("together"), together)

        var rng2: SeededRNG = SeededRNG(seed: 2)
        let blendSpec: ActivitySpec = ActivitySpec(unitId: "g-p", type: .blendToWord, knownOrder: 4)
        let b: Activity = try XCTUnwrap(ActivityGenerator.generate(curriculum: real.curriculum, index: real.index, spec: blendSpec, rng: &rng2))
        let miss: String = Feedback.text(for: b, answer: Answer(correct: false, support: .independent))
        XCTAssertTrue(miss.lowercased().contains("sound"), miss)
    }

    func testSessionEndMessageIsWarm() {
        XCTAssertTrue(Feedback.sessionEnd(activitiesDone: 0).contains("See you soon"))
        XCTAssertTrue(Feedback.sessionEnd(activitiesDone: 1).contains("1 activity"))
        XCTAssertTrue(Feedback.sessionEnd(activitiesDone: 12).contains("12 activities"))
    }
}
