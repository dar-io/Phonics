import XCTest
@testable import StorySoundsCore

// MARK: Shared time helpers

let t0: Date = Date(timeIntervalSince1970: 1_700_000_000)
func day(_ n: Int) -> Date { return t0.addingTimeInterval(Double(n) * 86_400) }

// MARK: Real bundled data (loaded once)

struct RealData {
    let curriculum: Curriculum
    let index: CurriculumIndex
}

enum TestData {
    static let real: RealData = {
        do {
            let c: Curriculum = try Curriculum.loadBundled()
            return RealData(curriculum: c, index: CurriculumIndex(c))
        } catch {
            fatalError("Could not load bundled curriculum: \(error)")
        }
    }()

    static let fixture: RealData = {
        let c: Curriculum = Fixture.curriculum()
        return RealData(curriculum: c, index: CurriculumIndex(c))
    }()
}

// MARK: Tiny hand-built curriculum

enum Fixture {
    static func unit(_ id: String, _ order: Int, _ phoneme: String, _ graphemes: [String], kind: UnitKind = .single,
                     prereqs: [String] = [], examples: [String] = [], tricky: [String] = [], misc: [String] = []) -> GraphemeUnit {
        return GraphemeUnit(id: id, order: order, phase: 2, stage: .reception, term: "test", phoneme: phoneme, graphemes: graphemes,
                            kind: kind, audioId: "ph-" + id, pronunciation: "p", prerequisites: prereqs, exampleWords: examples,
                            trickyWords: tricky, misconceptions: misc.map { Misconception(confusedWith: $0, guidance: "g") },
                            reviewIntervalsDays: nil, source: .inferred, citation: nil)
    }

    static func word(_ text: String, _ graphemes: [String], _ emoji: String? = nil) -> Word {
        return Word(text: text, graphemes: graphemes, emoji: emoji, pictureLabel: emoji == nil ? nil : text, concrete: emoji != nil)
    }

    static func w(_ text: String, _ graphemes: [String]) -> SentenceToken { return .word(text: text, graphemes: graphemes) }

    static func curriculum() -> Curriculum {
        let units: [GraphemeUnit] = [
            unit("g-s", 1, "/s/", ["s"], tricky: ["the", "is"], misc: ["z"]),
            unit("g-a", 2, "/a/", ["a"], prereqs: ["g-s"], examples: ["a"]),
            unit("g-t", 3, "/t/", ["t"], prereqs: ["g-a"], examples: ["at", "sat"]),
            unit("g-p", 4, "/p/", ["p"], prereqs: ["g-t"], examples: ["tap", "pat"]),
            unit("g-i", 5, "/i/", ["i"], prereqs: ["g-p"], examples: ["sip", "pit", "sit"], misc: ["a"]),
            unit("g-n", 6, "/n/", ["n"], prereqs: ["g-i"], examples: ["tin", "pin", "nap"], misc: ["m"]),
            unit("g-sh", 7, "/sh/", ["sh"], kind: .digraph, prereqs: ["g-n"], examples: ["ship"]),
            unit("g-ai", 8, "/ai/", ["ai"], kind: .digraph, prereqs: ["g-sh"], examples: ["pain"], tricky: ["said"]),
            unit("g-a-ai", 9, "/ai/", ["a"], kind: .alternative, prereqs: ["g-ai", "g-a"]),
            unit("p4-cvcc", 10, "adjacent consonants at the end (CVCC)", ["st", "nd"], kind: .alternative, prereqs: ["g-a-ai"],
                 examples: ["tint", "pant"]),
        ]
        let words: [Word] = [
            word("a", ["a"]), word("at", ["a", "t"]), word("sat", ["s", "a", "t"]),
            word("tap", ["t", "a", "p"], "🚰"), word("pat", ["p", "a", "t"], "👋"),
            word("sip", ["s", "i", "p"], "🥤"), word("pit", ["p", "i", "t"], "🕳️"), word("sit", ["s", "i", "t"], "🪑"),
            word("tin", ["t", "i", "n"], "🥫"), word("pin", ["p", "i", "n"], "📌"), word("nap", ["n", "a", "p"], "😴"),
            word("ship", ["sh", "i", "p"], "🚢"), word("pain", ["p", "ai", "n"], "🤕"),
            word("spa", ["s", "p", "a"], "💆"),
            word("tint", ["t", "i", "n", "t"]), word("pant", ["p", "a", "n", "t"]), word("pint", ["p", "i", "n", "t"]),
        ]
        let tricky: [TrickyWord] = [
            TrickyWord(text: "the", introducedAtOrder: 1, trickyPart: nil, decodablePartsKnown: nil),
            TrickyWord(text: "is", introducedAtOrder: 1, trickyPart: nil, decodablePartsKnown: nil),
            TrickyWord(text: "said", introducedAtOrder: 8, trickyPart: nil, decodablePartsKnown: nil),
        ]
        let pip: SentenceToken = w("Pip", ["p", "i", "p"])
        let sentences: [Sentence] = [
            Sentence(id: "s-1", text: "Pip sat.", tokens: [pip, w("sat", ["s", "a", "t"])], emoji: nil, pictureLabel: nil, unlockedByOrder: 5),
            Sentence(id: "s-2", text: "Tap it, Pip.", tokens: [w("Tap", ["t", "a", "p"]), w("it", ["i", "t"]), pip], emoji: nil, pictureLabel: nil, unlockedByOrder: 5),
            Sentence(id: "s-3", text: "The pin is in the tin.",
                     tokens: [.tricky(text: "The"), w("pin", ["p", "i", "n"]), .tricky(text: "is"), w("in", ["i", "n"]), .tricky(text: "the"), w("tin", ["t", "i", "n"])],
                     emoji: "🥫", pictureLabel: nil, unlockedByOrder: 6),
            Sentence(id: "s-4", text: "Pip sat in a ship.",
                     tokens: [pip, w("sat", ["s", "a", "t"]), w("in", ["i", "n"]), w("a", ["a"]), w("ship", ["sh", "i", "p"])],
                     emoji: "🚢", pictureLabel: nil, unlockedByOrder: 7),
            // Deliberately wrong stored unlock (2): the index must still gate it at 7 because of "ship".
            Sentence(id: "s-5", text: "Sit in the ship.",
                     tokens: [w("Sit", ["s", "i", "t"]), w("in", ["i", "n"]), .tricky(text: "the"), w("ship", ["sh", "i", "p"])],
                     emoji: nil, pictureLabel: nil, unlockedByOrder: 2),
        ]
        let stories: [Story] = [
            Story(id: "story-1", title: "Pip and the Tin", pages: [
                StoryPage(sentenceIds: ["s-1"], emoji: "🥫", pictureLabel: nil),
                StoryPage(sentenceIds: ["s-2"], emoji: "🥫", pictureLabel: nil),
            ]),
            Story(id: "story-2", title: "The Ship", pages: [
                StoryPage(sentenceIds: ["s-3"], emoji: nil, pictureLabel: nil),
                StoryPage(sentenceIds: ["s-4"], emoji: "🚢", pictureLabel: nil),
            ]),
        ]
        let requirements: [String: [String]] = [
            "spa": ["g-a-ai"], "tint": ["p4-cvcc"], "pant": ["p4-cvcc"], "pint": ["p4-cvcc"],
        ]
        return Curriculum(schemaVersion: CurriculumSchema.version, contentVersion: "fixture", units: units, words: words,
                          trickyWords: tricky, sentences: sentences, stories: stories, wordRequirements: requirements)
    }
}

// MARK: Learner helpers

func makeSnapshot(id: String = "learner") -> LearnerSnapshot {
    let profile: LearnerProfile = LearnerProfile(id: id, nickname: "Tester", createdAt: t0, contentVersion: "test")
    return LearnerSnapshot(profile: profile)
}

func makeAttempt(unit: String = "g-s", track: Track = .recognise, type: ActivityType = .listenChooseSound, item: String = "s",
                 correct: Bool, support: SupportLevel = .independent, session: String = "s1", ms: Int? = nil, at: Date = t0) -> Attempt {
    return Attempt(at: at, sessionId: session, unitId: unit, track: track, activityType: type, itemKey: item,
                   correct: correct, support: support, responseMs: ms)
}

/// One scripted independent result: (correct, session id, day offset, activity type).
typealias Step = (correct: Bool, session: String, day: Int, type: ActivityType)

func feed(_ skill: SkillState, _ steps: [Step], settings: MasterySettings = MasterySettings()) -> SkillState {
    var s: SkillState = skill
    for st in steps {
        let a: Attempt = makeAttempt(unit: s.unitId, track: s.track, type: st.type, correct: st.correct, session: st.session, at: day(st.day))
        s = Mastery.update(skill: s, attempt: a, settings: settings, now: day(st.day))
    }
    return s
}

/// 8 independent correct answers over 2 sessions, 2 days, 2 activity types: secure with the default settings.
func secureSteps() -> [Step] {
    return [
        (true, "a", 0, .listenChooseSound), (true, "a", 0, .findGrapheme), (true, "a", 0, .listenChooseSound), (true, "a", 0, .findGrapheme),
        (true, "b", 1, .listenChooseSound), (true, "b", 1, .findGrapheme), (true, "b", 1, .listenChooseSound), (true, "b", 1, .findGrapheme),
    ]
}

func secureSkill(_ unitId: String, _ track: Track, settings: MasterySettings = MasterySettings()) -> SkillState {
    return feed(SkillState(unitId: unitId, track: track), secureSteps(), settings: settings)
}

/// Snapshot where every APPLICABLE track of every unit with order <= `order` is secure (or only gate tracks when `allTracks` is false).
func snapshotWithSecure(index: CurriculumIndex, upTo order: Int, allTracks: Bool = false) -> LearnerSnapshot {
    var snap: LearnerSnapshot = makeSnapshot()
    for u in index.units where u.order <= order {
        let tracks: [Track] = allTracks ? index.applicableTracks(forUnit: u.id) : Progression.gateTracks(unit: u, index: index)
        for t in tracks { snap.skills.append(secureSkill(u.id, t)) }
    }
    return snap
}

// MARK: Activity validation

func tokens(of text: String) -> [String] {
    return text.lowercased().split(whereSeparator: { !$0.isLetter }).map { String($0) }
}

func payloadStrings(_ a: Activity) -> [String] {
    var out: [String] = [a.prompt]
    func addChoices(_ cs: [Choice]) { for c in cs { out.append(c.id); out.append(c.label) } }
    switch a.payload {
    case let .choose(choices, target, _): addChoices(choices); out.append(target)
    case let .blend(g, word, choices, _): addChoices(choices); out.append(word); out.append(contentsOf: g)
    case let .order(g, tiles, word, _): out.append(word); out.append(contentsOf: g); out.append(contentsOf: tiles)
    case let .segment(word, g, tiles, _): out.append(word); out.append(contentsOf: g); out.append(contentsOf: tiles)
    case let .build(word, g, tiles, _): out.append(word); out.append(contentsOf: g); out.append(contentsOf: tiles)
    case let .picture(word, choices): addChoices(choices); out.append(word)
    case let .tricky(word, choices): addChoices(choices); out.append(word)
    case let .sentence(t, _, choices, _): addChoices(choices); out.append(contentsOf: t)
    case let .story(title, pages, questions):
        out.append(title)
        for p in pages { for t in p.tokens { out.append(t.text) } }
        for q in questions { out.append(q.prompt); addChoices(q.choices) }
    case let .fluency(words, _): out.append(contentsOf: words)
    }
    return out
}

/// Words in `text` that are not part of the activity's own content (so a decodable word like "bad" never trips the banned list).
func templateTokens(_ text: String, content a: Activity) -> [String] {
    var content: Set<String> = []
    for s in payloadStrings(a) { for t in tokens(of: s) { content.insert(t) } }
    return tokens(of: text).filter { !content.contains($0) }
}

func exactlyOneCorrect(_ choices: [Choice], _ label: String) {
    XCTAssertEqual(choices.filter { $0.correct }.count, 1, "\(label): need exactly one correct choice")
    XCTAssertEqual(Set(choices.map { $0.id }).count, choices.count, "\(label): choice ids must be unique")
    XCTAssertGreaterThanOrEqual(choices.count, 1, "\(label): no choices")
}

func validateActivity(_ a: Activity, spec: ActivitySpec, index: CurriculumIndex) {
    let label: String = a.key
    guard let unit = index.unit(id: a.unitId) else { XCTFail("\(label): unknown unit \(a.unitId)"); return }
    let specOrder: Int = index.unitOrder(id: spec.unitId) ?? 0
    let k: Int = max(spec.knownOrder, specOrder)
    XCTAssertLessThanOrEqual(unit.order, k, "\(label): activity unit is above knownOrder")
    XCTAssertEqual(a.type, spec.type, label)
    XCTAssertEqual(a.track, ActivityGenerator.track(for: a.type), label)
    XCTAssertFalse(a.key.isEmpty)
    XCTAssertFalse(a.prompt.isEmpty, label)
    let taught: Set<String> = index.taughtGraphemes(upToOrder: k)
    for g in a.graphemesUsed { XCTAssertTrue(taught.contains(g), "\(label): untaught grapheme '\(g)' (known order \(k))") }
    for t in a.trickyUsed { XCTAssertTrue(index.isTrickyIntroduced(t, atOrder: k), "\(label): tricky word '\(t)' not introduced") }
    for s in [a.prompt, a.spokenPrompt] {
        for t in tokens(of: s) { XCTAssertFalse(Feedback.bannedWords.contains(t), "\(label): banned word '\(t)' in prompt") }
    }

    func decodableWord(_ text: String) {
        guard let w = index.word(text: text) else { XCTFail("\(label): '\(text)' is not a curriculum word"); return }
        XCTAssertTrue(index.isWordDecodable(w, atOrder: k), "\(label): '\(text)' not decodable at \(k)")
        for g in w.graphemes { XCTAssertTrue(taught.contains(g), "\(label): '\(text)' uses untaught '\(g)'") }
    }
    func joins(_ graphemes: [String], _ word: String) {
        XCTAssertEqual(GraphemeText.join(graphemes), word.lowercased(), "\(label): graphemes do not spell the word")
        for g in graphemes { XCTAssertTrue(taught.contains(g), "\(label): untaught grapheme '\(g)'") }
    }
    func sameMultiset(_ a1: [String], _ a2: [String]) -> Bool { return a1.sorted() == a2.sorted() }

    switch a.payload {
    case let .choose(choices, target, _):
        exactlyOneCorrect(choices, label)
        if a.type == .matchSoundGrapheme {
            XCTAssertTrue(taught.contains(target), "\(label): target not taught")
            for c in choices {
                guard let cu = index.unit(id: c.id) else { XCTFail("\(label): sound choice is not a unit"); continue }
                XCTAssertLessThanOrEqual(cu.order, k, label)
                if !c.correct { XCTAssertFalse(cu.graphemes.contains(target), "\(label): another sound is also valid for '\(target)'") }
            }
            XCTAssertEqual(choices.first(where: { $0.correct })?.id, a.unitId, label)
        } else {
            XCTAssertEqual(choices.first(where: { $0.correct })?.id, target, label)
            for c in choices { XCTAssertTrue(taught.contains(c.id), "\(label): untaught choice '\(c.id)'") }
            // No distractor may make the same sound as the target.
            let sharing: Set<String> = index.graphemesSharingSound(with: unit, atOrder: k)
            for c in choices where !c.correct { XCTAssertFalse(sharing.contains(c.id), "\(label): '\(c.id)' sounds like the target") }
        }
    case let .blend(graphemes, word, choices, _):
        exactlyOneCorrect(choices, label)
        joins(graphemes, word)
        XCTAssertEqual(choices.first(where: { $0.correct })?.id, word, label)
        for c in choices { decodableWord(c.id) }
    case let .order(graphemes, tiles, word, _):
        joins(graphemes, word)
        XCTAssertTrue(sameMultiset(graphemes, tiles), "\(label): tiles must be the word's sounds")
        if Set(graphemes).count > 1 { XCTAssertNotEqual(graphemes, tiles, "\(label): tiles should be shuffled") }
        decodableWord(word)
    case let .segment(word, graphemes, tiles, _), let .build(word, graphemes, tiles, _):
        joins(graphemes, word)
        decodableWord(word)
        var remaining: [String] = tiles
        for g in graphemes {
            if let i = remaining.firstIndex(of: g) { remaining.remove(at: i) } else { XCTFail("\(label): tile for '\(g)' missing") }
        }
        for t in tiles { XCTAssertTrue(taught.contains(t), "\(label): untaught tile '\(t)'") }
    case let .picture(word, choices):
        exactlyOneCorrect(choices, label)
        XCTAssertEqual(choices.first(where: { $0.correct })?.id, word, label)
        for c in choices { decodableWord(c.id) }
        XCTAssertEqual(Set(choices.compactMap { $0.emoji }).count, choices.count, "\(label): pictures must differ")
    case let .tricky(word, choices):
        exactlyOneCorrect(choices, label)
        XCTAssertEqual(choices.first(where: { $0.correct })?.id, word, label)
        for c in choices { XCTAssertTrue(index.isTrickyIntroduced(c.id, atOrder: k), "\(label): tricky '\(c.id)' not introduced") }
    case let .sentence(toks, blankIndex, choices, _):
        exactlyOneCorrect(choices, label)
        XCTAssertTrue(blankIndex >= 0 && blankIndex < toks.count, label)
        if blankIndex >= 0 && blankIndex < toks.count { XCTAssertEqual(toks[blankIndex], "___", label) }
        for c in choices where !c.correct { decodableWord(c.id.lowercased()) }
    case let .story(_, pages, questions):
        XCTAssertFalse(pages.isEmpty, label)
        for p in pages { for t in p.tokens where t.tricky { XCTAssertTrue(index.isTrickyIntroduced(t.text, atOrder: k), "\(label): tricky '\(t.text)'") } }
        for q in questions {
            exactlyOneCorrect(q.choices, label)
            for c in q.choices where !c.correct { decodableWord(c.id) }
        }
    case let .fluency(words, _):
        XCTAssertGreaterThanOrEqual(words.count, 3, label)
        for w in words { decodableWord(w) }
    }
}
