import Foundation

/// What to generate. `knownOrder` is the highest unit order the learner has been taught; it is raised to the target
/// unit's own order so the target is always included. Nothing above it ever appears in an activity.
public struct ActivitySpec: Hashable, Sendable {
    public var unitId: String
    public var type: ActivityType
    public var knownOrder: Int
    /// Desired number of choices for choice-based activities (clamped to what the taught content can supply).
    public var choiceCount: Int
    /// Item keys to avoid when fresh alternatives exist (the generator repeats an item only if it has nothing else).
    public var excludeKeys: Set<String>

    public init(unitId: String, type: ActivityType, knownOrder: Int, choiceCount: Int = 3, excludeKeys: Set<String> = []) {
        self.unitId = unitId
        self.type = type
        self.knownOrder = knownOrder
        self.choiceCount = choiceCount
        self.excludeKeys = excludeKeys
    }
}

/// Everything the builders need for one (unit, knownOrder) pair.
struct GenContext {
    let index: CurriculumIndex
    let unit: GraphemeUnit
    let k: Int
    let taughtList: [String]
    let taughtSet: Set<String>
    let unitGraphemes: [String]
    let focus: [Word]
    let decodable: [Word]

    init(index: CurriculumIndex, unit: GraphemeUnit, knownOrder: Int) {
        let order: Int = max(knownOrder, unit.order)
        self.index = index
        self.unit = unit
        self.k = order
        self.taughtList = index.taughtGraphemeList(upToOrder: order)
        self.taughtSet = index.taughtGraphemes(upToOrder: order)
        if index.isConsolidation(unit) {
            self.unitGraphemes = []
        } else {
            let taught: Set<String> = index.taughtGraphemes(upToOrder: order)
            self.unitGraphemes = unit.graphemes.filter { taught.contains($0) }
        }
        self.focus = index.focusWords(forUnit: unit, atOrder: order)
        self.decodable = index.decodableWords(atOrder: order)
    }

    var focusMulti: [Word] { return focus.filter { $0.graphemes.count >= 2 } }
    var decodableMulti: [Word] { return decodable.filter { $0.graphemes.count >= 2 } }
    var emojiWords: [Word] { return decodable.filter { ($0.emoji ?? "").isEmpty == false } }
}

struct SentenceBlank {
    let sentence: Sentence
    let index: Int
}

public enum ActivityGenerator {

    // MARK: Type / track tables

    public static func track(for type: ActivityType) -> Track {
        switch type {
        case .listenChooseSound, .matchSoundGrapheme, .findGrapheme, .mixedReview: return .recognise
        case .blendToWord, .orderSounds: return .blend
        case .segmentWord, .buildWord: return .segment
        case .readPickPicture, .identifyTricky, .completeSentence, .readStory, .fluency: return .read
        }
    }

    /// Activity types that practise a track for one specific unit (story and mixed review are session-level extras).
    public static func coreTypes(for track: Track) -> [ActivityType] {
        switch track {
        case .recognise: return [.listenChooseSound, .matchSoundGrapheme, .findGrapheme]
        case .blend: return [.blendToWord, .orderSounds]
        case .segment: return [.segmentWord, .buildWord]
        case .read: return [.readPickPicture, .identifyTricky, .completeSentence, .fluency]
        }
    }

    static func key(_ type: ActivityType, _ unitId: String, _ parts: String...) -> String {
        var all: [String] = [type.rawValue, unitId]
        all.append(contentsOf: parts)
        return all.joined(separator: "|")
    }

    static func unique(_ items: [String]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for s in items where seen.insert(s).inserted { out.append(s) }
        return out
    }

    // MARK: Support

    /// Which activity types can be produced for `unitId` when the learner knows units up to `knownOrder`.
    public static func supportedTypes(index: CurriculumIndex, unitId: String, knownOrder: Int) -> [ActivityType] {
        guard let unit = index.unit(id: unitId) else { return [] }
        return supportedTypes(GenContext(index: index, unit: unit, knownOrder: knownOrder))
    }

    static func supportedTypes(_ ctx: GenContext) -> [ActivityType] {
        return ActivityType.allCases.filter { supports($0, ctx) }
    }

    static func applicableTracks(index: CurriculumIndex, unit: GraphemeUnit) -> [Track] {
        let ctx: GenContext = GenContext(index: index, unit: unit, knownOrder: unit.order)
        let supported: [ActivityType] = supportedTypes(ctx)
        var tracks: [Track] = []
        for t in Track.allCases {
            if coreTypes(for: t).contains(where: { supported.contains($0) }) { tracks.append(t) }
        }
        return tracks
    }

    static func mixedPool(_ ctx: GenContext) -> [(unit: GraphemeUnit, grapheme: String)] {
        var out: [(unit: GraphemeUnit, grapheme: String)] = []
        for u in ctx.index.units(upToOrder: ctx.k) where !ctx.index.isConsolidation(u) {
            for g in u.graphemes { out.append((unit: u, grapheme: g)) }
        }
        return out
    }

    static func unitTricky(_ ctx: GenContext) -> [String] {
        return unique(ctx.unit.trickyWords.filter { ctx.index.isTrickyIntroduced($0, atOrder: ctx.k) })
    }

    static func introducedTricky(_ ctx: GenContext) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for t in ctx.index.trickyWords(introducedByOrder: ctx.k) where seen.insert(t.text.lowercased()).inserted {
            out.append(t.text)
        }
        return out
    }

    static func sentenceCandidates(_ ctx: GenContext) -> [SentenceBlank] {
        if ctx.decodable.count < 2 { return [] }
        let focusKeys: Set<String> = Set(ctx.focus.map { $0.text.lowercased() })
        var out: [SentenceBlank] = []
        for s in ctx.index.decodableSentences(atOrder: ctx.k) {
            let isNew: Bool = ctx.index.unlockOrder(forSentence: s) == ctx.unit.order
            var focusIdx: [Int] = []
            var wordIdx: [Int] = []
            for (i, t) in s.tokens.enumerated() {
                if case let .word(text, _) = t {
                    wordIdx.append(i)
                    if focusKeys.contains(text.lowercased()) { focusIdx.append(i) }
                }
            }
            if focusIdx.isEmpty && !isNew { continue }
            let use: [Int] = focusIdx.isEmpty ? wordIdx : focusIdx
            for i in use { out.append(SentenceBlank(sentence: s, index: i)) }
        }
        return out
    }

    static func supports(_ type: ActivityType, _ ctx: GenContext) -> Bool {
        switch type {
        case .listenChooseSound, .findGrapheme, .matchSoundGrapheme:
            return !ctx.unitGraphemes.isEmpty
        case .mixedReview:
            return !mixedPool(ctx).isEmpty
        case .blendToWord:
            return !ctx.focusMulti.isEmpty && ctx.decodable.count >= 2
        case .orderSounds, .segmentWord, .buildWord:
            return !ctx.focusMulti.isEmpty
        case .readPickPicture:
            let focusEmoji: [Word] = ctx.focus.filter { ($0.emoji ?? "").isEmpty == false }
            if focusEmoji.isEmpty { return false }
            return Set(ctx.emojiWords.compactMap { $0.emoji }).count >= 2
        case .identifyTricky:
            return !unitTricky(ctx).isEmpty && introducedTricky(ctx).count >= 2
        case .completeSentence:
            return !sentenceCandidates(ctx).isEmpty
        case .readStory:
            return !ctx.index.decodableStories(atOrder: ctx.k).isEmpty
        case .fluency:
            return !ctx.focusMulti.isEmpty && ctx.decodableMulti.count >= 3
        }
    }

    // MARK: Generate

    /// Builds one activity, or nil when the taught content cannot support the requested type (see `supportedTypes`).
    public static func generate(curriculum: Curriculum, index: CurriculumIndex, spec: ActivitySpec, rng: inout SeededRNG) -> Activity? {
        guard let unit = index.unit(id: spec.unitId) else { return nil }
        let ctx: GenContext = GenContext(index: index, unit: unit, knownOrder: spec.knownOrder)
        if !supports(spec.type, ctx) { return nil }
        switch spec.type {
        case .listenChooseSound, .findGrapheme:
            return buildChooseGrapheme(type: spec.type, ctx: ctx, spec: spec, rng: &rng)
        case .matchSoundGrapheme:
            return buildMatchSound(ctx: ctx, spec: spec, rng: &rng)
        case .mixedReview:
            return buildMixed(ctx: ctx, spec: spec, rng: &rng)
        case .blendToWord:
            return buildBlend(ctx: ctx, spec: spec, rng: &rng)
        case .orderSounds:
            return buildOrder(ctx: ctx, spec: spec, rng: &rng)
        case .segmentWord:
            return buildSegment(ctx: ctx, spec: spec, rng: &rng)
        case .buildWord:
            return buildBuild(ctx: ctx, spec: spec, rng: &rng)
        case .readPickPicture:
            return buildPicture(ctx: ctx, spec: spec, rng: &rng)
        case .identifyTricky:
            return buildTricky(ctx: ctx, spec: spec, rng: &rng)
        case .completeSentence:
            return buildSentence(ctx: ctx, spec: spec, rng: &rng)
        case .readStory:
            return buildStory(ctx: ctx, spec: spec, rng: &rng)
        case .fluency:
            return buildFluency(ctx: ctx, spec: spec, rng: &rng)
        }
    }

    // MARK: Shared helpers

    private static func pickFresh<T>(_ items: [T], keyOf: (T) -> String, spec: ActivitySpec, rng: inout SeededRNG) -> T? {
        let fresh: [T] = items.filter { !spec.excludeKeys.contains(keyOf($0)) }
        return rng.pick(fresh.isEmpty ? items : fresh)
    }

    private static func wordChoice(_ word: Word, correct: Bool) -> Choice {
        return Choice(id: word.text, label: word.text, audioId: "w-" + word.text, emoji: nil, correct: correct)
    }

    private static func differingPositions(_ a: [String], _ b: [String]) -> Int {
        if a.count != b.count { return Int.max }
        var n: Int = 0
        for i in 0..<a.count where a[i] != b[i] { n += 1 }
        return n
    }

    /// Distractor words from `pool`: near-misses (one grapheme different) first, then similar shapes, then anything.
    private static func wordDistractors(target: Word, pool: [Word], count: Int, rng: inout SeededRNG) -> [Word] {
        if count <= 0 { return [] }
        var seen: Set<String> = [target.text.lowercased()]
        var near: [Word] = []
        var similar: [Word] = []
        var rest: [Word] = []
        for w in pool {
            let key: String = w.text.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            if differingPositions(target.graphemes, w.graphemes) == 1 {
                near.append(w)
            } else if w.graphemes.count == target.graphemes.count
                        || w.graphemes.first == target.graphemes.first
                        || w.graphemes.last == target.graphemes.last {
                similar.append(w)
            } else {
                rest.append(w)
            }
        }
        var ordered: [Word] = rng.shuffled(near)
        ordered.append(contentsOf: rng.shuffled(similar))
        if ordered.count < count { ordered.append(contentsOf: rng.shuffled(rest)) }
        return Array(ordered.prefix(count))
    }

    private static func graphemeDistractors(target: String, ctx: GenContext, count: Int, rng: inout SeededRNG) -> [String] {
        if count <= 0 { return [] }
        var excluded: Set<String> = ctx.index.graphemesSharingSound(with: ctx.unit, atOrder: ctx.k)
        excluded.insert(target)
        var tier1: [String] = []
        for m in ctx.unit.misconceptions {
            for g in ctx.index.resolveGraphemes(m.confusedWith, atOrder: ctx.k) where !excluded.contains(g) && !tier1.contains(g) {
                tier1.append(g)
            }
        }
        let targetChars: Set<Character> = Set(target)
        var similar: [String] = []
        var rest: [String] = []
        for g in ctx.taughtList where !excluded.contains(g) && !tier1.contains(g) {
            if targetChars.isDisjoint(with: Set(g)) { rest.append(g) } else { similar.append(g) }
        }
        var ordered: [String] = rng.shuffled(tier1)
        ordered.append(contentsOf: rng.shuffled(similar))
        ordered.append(contentsOf: rng.shuffled(rest))
        return Array(ordered.prefix(count))
    }

    private static func shuffledTiles(_ target: [String], rng: inout SeededRNG) -> [String] {
        var tiles: [String] = rng.shuffled(target)
        var tries: Int = 0
        while tiles == target && tries < 6 && Set(target).count > 1 {
            tiles = rng.shuffled(target)
            tries += 1
        }
        return tiles
    }

    private static func soundAudio(_ graphemes: [String], ctx: GenContext) -> [String] {
        var ids: [String] = []
        for g in graphemes {
            if let a = ctx.index.audioId(forGrapheme: g, atOrder: ctx.k) { ids.append(a) }
        }
        return ids
    }

    // MARK: Recognise

    private static func buildChooseGrapheme(type: ActivityType, ctx: GenContext, spec: ActivitySpec, rng: inout SeededRNG) -> Activity? {
        guard let target = pickFresh(ctx.unitGraphemes, keyOf: { key(type, ctx.unit.id, $0) }, spec: spec, rng: &rng) else { return nil }
        let desired: Int = type == .findGrapheme ? min(6, spec.choiceCount + 1) : spec.choiceCount
        return makeGraphemeChoice(type: type, ctx: ctx, target: target, desired: desired, rng: &rng)
    }

    private static func makeGraphemeChoice(type: ActivityType, ctx: GenContext, target: String, desired: Int, rng: inout SeededRNG) -> Activity {
        let unit: GraphemeUnit = ctx.unit
        let distractors: [String] = graphemeDistractors(target: target, ctx: ctx, count: max(0, desired - 1), rng: &rng)
        var choices: [Choice] = [Choice(id: target, label: target, audioId: unit.audioId, emoji: nil, correct: true)]
        for d in distractors {
            choices.append(Choice(id: d, label: d, audioId: ctx.index.audioId(forGrapheme: d, atOrder: ctx.k), emoji: nil, correct: false))
        }
        choices = rng.shuffled(choices)
        let prompt: String
        let spoken: String
        var audio: [String]
        if type == .findGrapheme {
            prompt = "Find the letters for the sound \(unit.phoneme)"
            spoken = "Find the sound. Which letters say it?"
            audio = ["i-find-the-sound", unit.audioId]
        } else {
            prompt = "Which letters make this sound?"
            spoken = "Listen. Which letters make this sound?"
            audio = ["i-listen", unit.audioId]
        }
        audio = unique(audio)
        return Activity(key: key(type, unit.id, target), type: type, unitId: unit.id, track: .recognise,
                        prompt: prompt, spokenPrompt: spoken, audioIds: audio,
                        payload: .choose(choices: choices, target: target, emoji: nil),
                        graphemesUsed: unique([target] + distractors), trickyUsed: [])
    }

    private static func buildMatchSound(ctx: GenContext, spec: ActivitySpec, rng: inout SeededRNG) -> Activity? {
        let type: ActivityType = .matchSoundGrapheme
        let unit: GraphemeUnit = ctx.unit
        guard let target = pickFresh(ctx.unitGraphemes, keyOf: { key(type, unit.id, $0) }, spec: spec, rng: &rng) else { return nil }
        let keys: Set<String> = ctx.index.phonemeKeys(of: unit)
        var confused: [String] = []
        for m in unit.misconceptions { confused.append(contentsOf: ctx.index.resolveGraphemes(m.confusedWith, atOrder: ctx.k)) }
        var tier1: [GraphemeUnit] = []
        var rest: [GraphemeUnit] = []
        for u in ctx.index.units(upToOrder: ctx.k) where !ctx.index.isConsolidation(u) && u.id != unit.id {
            // The grapheme may legitimately make that sound too, or the sounds are the same: not a fair distractor.
            if u.graphemes.contains(target) { continue }
            if !ctx.index.phonemeKeys(of: u).isDisjoint(with: keys) { continue }
            if u.graphemes.contains(where: { confused.contains($0) }) { tier1.append(u) } else { rest.append(u) }
        }
        var ordered: [GraphemeUnit] = rng.shuffled(tier1)
        ordered.append(contentsOf: rng.shuffled(rest))
        var chosen: [GraphemeUnit] = []
        var usedKeys: [Set<String>] = [keys]
        let wanted: Int = max(0, spec.choiceCount - 1)
        for u in ordered {
            if chosen.count >= wanted { break }
            let pk: Set<String> = ctx.index.phonemeKeys(of: u)
            if usedKeys.contains(where: { !$0.isDisjoint(with: pk) }) { continue }
            chosen.append(u)
            usedKeys.append(pk)
        }
        var choices: [Choice] = [Choice(id: unit.id, label: unit.phoneme, audioId: unit.audioId, emoji: nil, correct: true)]
        for u in chosen { choices.append(Choice(id: u.id, label: u.phoneme, audioId: u.audioId, emoji: nil, correct: false)) }
        choices = rng.shuffled(choices)
        return Activity(key: key(type, unit.id, target), type: type, unitId: unit.id, track: .recognise,
                        prompt: "Which sound do these letters make? \(target)",
                        spokenPrompt: "Touch each letter and say its sound. Which sound does it make?",
                        audioIds: ["i-touch-and-say"],
                        payload: .choose(choices: choices, target: target, emoji: nil),
                        graphemesUsed: [target], trickyUsed: [])
    }

    private static func buildMixed(ctx: GenContext, spec: ActivitySpec, rng: inout SeededRNG) -> Activity? {
        let type: ActivityType = .mixedReview
        let pool: [(unit: GraphemeUnit, grapheme: String)] = mixedPool(ctx)
        if pool.isEmpty { return nil }
        let fresh = pool.filter { !spec.excludeKeys.contains(key(type, $0.unit.id, $0.grapheme)) }
        let source = fresh.isEmpty ? pool : fresh
        guard let pick = rng.pick(source) else { return nil }
        let sub: GenContext = GenContext(index: ctx.index, unit: pick.unit, knownOrder: ctx.k)
        return makeGraphemeChoice(type: type, ctx: sub, target: pick.grapheme, desired: spec.choiceCount, rng: &rng)
    }

    // MARK: Blend / segment / build

    private static func buildBlend(ctx: GenContext, spec: ActivitySpec, rng: inout SeededRNG) -> Activity? {
        let type: ActivityType = .blendToWord
        guard let target = pickFresh(ctx.focusMulti, keyOf: { key(type, ctx.unit.id, $0.text) }, spec: spec, rng: &rng) else { return nil }
        let distractors: [Word] = wordDistractors(target: target, pool: ctx.decodable, count: max(1, spec.choiceCount - 1), rng: &rng)
        if distractors.isEmpty { return nil }
        var choices: [Choice] = [wordChoice(target, correct: true)]
        for d in distractors { choices.append(wordChoice(d, correct: false)) }
        choices = rng.shuffled(choices)
        var graphemes: [String] = target.graphemes
        for d in distractors { graphemes.append(contentsOf: d.graphemes) }
        var audio: [String] = ["i-lets-sound-it-out"]
        audio.append(contentsOf: soundAudio(target.graphemes, ctx: ctx))
        return Activity(key: key(type, ctx.unit.id, target.text), type: type, unitId: ctx.unit.id, track: .blend,
                        prompt: "Blend the sounds. Which word is it?",
                        spokenPrompt: "Let's sound it out together. Which word do the sounds make?",
                        audioIds: unique(audio),
                        payload: .blend(graphemes: target.graphemes, word: target.text, choices: choices, emoji: target.emoji),
                        graphemesUsed: unique(graphemes), trickyUsed: [])
    }

    private static func buildOrder(ctx: GenContext, spec: ActivitySpec, rng: inout SeededRNG) -> Activity? {
        let type: ActivityType = .orderSounds
        guard let target = pickFresh(ctx.focusMulti, keyOf: { key(type, ctx.unit.id, $0.text) }, spec: spec, rng: &rng) else { return nil }
        let tiles: [String] = shuffledTiles(target.graphemes, rng: &rng)
        return Activity(key: key(type, ctx.unit.id, target.text), type: type, unitId: ctx.unit.id, track: .blend,
                        prompt: "Put the sounds in order to make the word.",
                        spokenPrompt: "Listen to the word. Choose the sounds in the order you hear them.",
                        audioIds: ["i-listen", "w-" + target.text],
                        payload: .order(graphemes: target.graphemes, tiles: tiles, word: target.text, emoji: target.emoji),
                        graphemesUsed: unique(target.graphemes), trickyUsed: [])
    }

    private static func buildSegment(ctx: GenContext, spec: ActivitySpec, rng: inout SeededRNG) -> Activity? {
        let type: ActivityType = .segmentWord
        guard let target = pickFresh(ctx.focusMulti, keyOf: { key(type, ctx.unit.id, $0.text) }, spec: spec, rng: &rng) else { return nil }
        var extra: [String] = []
        for g in target.graphemes where g.count > 1 && !GraphemeText.isSplit(g) {
            let pieces: [String] = g.map { String($0) }
            if pieces.allSatisfy({ ctx.taughtSet.contains($0) }) {
                for p in pieces where !extra.contains(p) { extra.append(p) }
            }
        }
        extra = Array(extra.prefix(2))
        let tiles: [String] = rng.shuffled(target.graphemes + extra)
        return Activity(key: key(type, ctx.unit.id, target.text), type: type, unitId: ctx.unit.id, track: .segment,
                        prompt: "Split the word into its sounds.",
                        spokenPrompt: "Listen to the word. Choose its sounds, one at a time, in order.",
                        audioIds: ["i-listen", "w-" + target.text],
                        payload: .segment(word: target.text, graphemes: target.graphemes, tiles: tiles, emoji: target.emoji),
                        graphemesUsed: unique(target.graphemes + extra), trickyUsed: [])
    }

    private static func buildBuild(ctx: GenContext, spec: ActivitySpec, rng: inout SeededRNG) -> Activity? {
        let type: ActivityType = .buildWord
        guard let target = pickFresh(ctx.focusMulti, keyOf: { key(type, ctx.unit.id, $0.text) }, spec: spec, rng: &rng) else { return nil }
        let wordText: String = target.text.lowercased()
        let wanted: Int = spec.choiceCount >= 3 ? 2 : 1
        var confused: [String] = []
        for m in ctx.unit.misconceptions { confused.append(contentsOf: ctx.index.resolveGraphemes(m.confusedWith, atOrder: ctx.k)) }
        var tier1: [String] = []
        var rest: [String] = []
        for g in ctx.taughtList {
            if target.graphemes.contains(g) { continue }
            if GraphemeText.isSplit(g) { continue }
            if wordText.contains(g) { continue }
            if confused.contains(g) { tier1.append(g) } else { rest.append(g) }
        }
        var ordered: [String] = rng.shuffled(tier1)
        ordered.append(contentsOf: rng.shuffled(rest))
        let extra: [String] = Array(ordered.prefix(wanted))
        let tiles: [String] = rng.shuffled(target.graphemes + extra)
        return Activity(key: key(type, ctx.unit.id, target.text), type: type, unitId: ctx.unit.id, track: .segment,
                        prompt: "Build the word.",
                        spokenPrompt: "Listen to the word. Choose the letters to build it, in order.",
                        audioIds: ["i-listen", "w-" + target.text],
                        payload: .build(word: target.text, graphemes: target.graphemes, tiles: tiles, emoji: target.emoji),
                        graphemesUsed: unique(target.graphemes + extra), trickyUsed: [])
    }

    // MARK: Read

    private static func buildPicture(ctx: GenContext, spec: ActivitySpec, rng: inout SeededRNG) -> Activity? {
        let type: ActivityType = .readPickPicture
        let focusEmoji: [Word] = ctx.focus.filter { ($0.emoji ?? "").isEmpty == false }
        guard let target = pickFresh(focusEmoji, keyOf: { key(type, ctx.unit.id, $0.text) }, spec: spec, rng: &rng) else { return nil }
        let targetLabel: String = (target.pictureLabel ?? target.text).lowercased()
        var seenEmoji: Set<String> = [target.emoji ?? ""]
        var pool: [Word] = []
        for w in ctx.emojiWords {
            let e: String = w.emoji ?? ""
            if w.text.lowercased() == target.text.lowercased() { continue }
            if (w.pictureLabel ?? w.text).lowercased() == targetLabel { continue }
            if seenEmoji.contains(e) { continue }
            seenEmoji.insert(e)
            pool.append(w)
        }
        let distractors: [Word] = wordDistractors(target: target, pool: pool, count: max(1, spec.choiceCount - 1), rng: &rng)
        if distractors.isEmpty { return nil }
        var choices: [Choice] = [Choice(id: target.text, label: target.pictureLabel ?? target.text, audioId: nil, emoji: target.emoji, correct: true)]
        for d in distractors {
            choices.append(Choice(id: d.text, label: d.pictureLabel ?? d.text, audioId: nil, emoji: d.emoji, correct: false))
        }
        choices = rng.shuffled(choices)
        var graphemes: [String] = target.graphemes
        for d in distractors { graphemes.append(contentsOf: d.graphemes) }
        return Activity(key: key(type, ctx.unit.id, target.text), type: type, unitId: ctx.unit.id, track: .read,
                        prompt: "Read the word. Which picture matches?",
                        spokenPrompt: "Read the word. Which picture matches it?",
                        audioIds: ["i-match-the-picture"],
                        payload: .picture(word: target.text, choices: choices),
                        graphemesUsed: unique(graphemes), trickyUsed: [])
    }

    private static func buildTricky(ctx: GenContext, spec: ActivitySpec, rng: inout SeededRNG) -> Activity? {
        let type: ActivityType = .identifyTricky
        guard let target = pickFresh(unitTricky(ctx), keyOf: { key(type, ctx.unit.id, $0) }, spec: spec, rng: &rng) else { return nil }
        let tKey: String = target.lowercased()
        var similar: [String] = []
        var rest: [String] = []
        for t in introducedTricky(ctx) where t.lowercased() != tKey {
            if t.lowercased().first == tKey.first || t.count == target.count { similar.append(t) } else { rest.append(t) }
        }
        var ordered: [String] = rng.shuffled(similar)
        ordered.append(contentsOf: rng.shuffled(rest))
        let distractors: [String] = Array(ordered.prefix(max(1, spec.choiceCount - 1)))
        if distractors.isEmpty { return nil }
        var choices: [Choice] = [Choice(id: target, label: target, audioId: "w-" + target, emoji: nil, correct: true)]
        for d in distractors { choices.append(Choice(id: d, label: d, audioId: "w-" + d, emoji: nil, correct: false)) }
        choices = rng.shuffled(choices)
        return Activity(key: key(type, ctx.unit.id, target), type: type, unitId: ctx.unit.id, track: .read,
                        prompt: "This is a tricky word. Can you find it?",
                        spokenPrompt: "This is a tricky word. Listen, then find it.",
                        audioIds: ["i-tricky-word", "w-" + target],
                        payload: .tricky(word: target, choices: choices),
                        graphemesUsed: [], trickyUsed: unique([target] + distractors))
    }

    private static func matchCase(_ text: String, like model: String) -> String {
        guard let f = model.first, f.isUppercase, let g = text.first else { return text }
        return String(g).uppercased() + String(text.dropFirst())
    }

    private static func buildSentence(ctx: GenContext, spec: ActivitySpec, rng: inout SeededRNG) -> Activity? {
        let type: ActivityType = .completeSentence
        let candidates: [SentenceBlank] = sentenceCandidates(ctx)
        guard let pick = pickFresh(candidates, keyOf: { key(type, ctx.unit.id, $0.sentence.id, String($0.index)) }, spec: spec, rng: &rng) else { return nil }
        let sentence: Sentence = pick.sentence
        guard case let .word(targetText, targetGraphemes) = sentence.tokens[pick.index] else { return nil }
        let target: Word = ctx.index.word(text: targetText) ?? Word(text: targetText, graphemes: targetGraphemes, emoji: nil, pictureLabel: nil, concrete: nil)
        let distractors: [Word] = wordDistractors(target: target, pool: ctx.decodable, count: max(1, spec.choiceCount - 1), rng: &rng)
        if distractors.isEmpty { return nil }
        var choices: [Choice] = [Choice(id: targetText, label: targetText, audioId: "w-" + targetText.lowercased(), emoji: nil, correct: true)]
        var seenIds: Set<String> = [targetText]
        for d in distractors {
            let shown: String = matchCase(d.text, like: targetText)
            if seenIds.insert(shown).inserted {
                choices.append(Choice(id: shown, label: shown, audioId: "w-" + d.text, emoji: nil, correct: false))
            }
        }
        choices = rng.shuffled(choices)
        var tokens: [String] = []
        var graphemes: [String] = []
        var tricky: [String] = []
        for (i, t) in sentence.tokens.enumerated() {
            tokens.append(i == pick.index ? "___" : t.text)
            switch t {
            case let .word(_, g): graphemes.append(contentsOf: g)
            case let .tricky(text): tricky.append(text)
            }
        }
        for d in distractors { graphemes.append(contentsOf: d.graphemes) }
        return Activity(key: key(type, ctx.unit.id, sentence.id, String(pick.index)), type: type, unitId: ctx.unit.id, track: .read,
                        prompt: "Read the sentence. Which word fits?",
                        spokenPrompt: "Read the sentence. Which word goes in the gap?",
                        audioIds: ["i-read-the-sentence"],
                        payload: .sentence(tokens: tokens, blankIndex: pick.index, choices: choices, emoji: sentence.emoji),
                        graphemesUsed: unique(graphemes), trickyUsed: unique(tricky))
    }

    private static func buildStory(ctx: GenContext, spec: ActivitySpec, rng: inout SeededRNG) -> Activity? {
        let type: ActivityType = .readStory
        var stories: [Story] = ctx.index.decodableStories(atOrder: ctx.k)
        if stories.isEmpty { return nil }
        // Prefer the most recently unlocked stories (they use the newest sounds).
        stories.reverse()
        let top: [Story] = Array(stories.prefix(4))
        guard let story = pickFresh(top, keyOf: { key(type, ctx.unit.id, $0.id) }, spec: spec, rng: &rng) else { return nil }
        var pages: [StoryPageContent] = []
        var graphemes: [String] = []
        var tricky: [String] = []
        var storyWords: [String] = []
        var storyWordKeys: Set<String> = []
        for page in story.pages {
            var toks: [(text: String, tricky: Bool)] = []
            for sid in page.sentenceIds {
                guard let s = ctx.index.sentence(id: sid) else { continue }
                for t in s.tokens {
                    switch t {
                    case let .word(text, g):
                        toks.append((text: text, tricky: false))
                        graphemes.append(contentsOf: g)
                        if storyWordKeys.insert(text.lowercased()).inserted { storyWords.append(text) }
                    case let .tricky(text):
                        toks.append((text: text, tricky: true))
                        tricky.append(text)
                    }
                }
            }
            pages.append(StoryPageContent(tokens: toks, emoji: page.emoji))
        }
        var questions: [StoryQuestion] = []
        if let answer = rng.pick(storyWords) {
            let notInStory: [Word] = ctx.decodable.filter { !storyWordKeys.contains($0.text.lowercased()) }
            let wrong: [Word] = wordDistractors(target: Word(text: answer, graphemes: [], emoji: nil, pictureLabel: nil, concrete: nil),
                                                pool: notInStory, count: max(1, spec.choiceCount - 1), rng: &rng)
            if !wrong.isEmpty {
                var qChoices: [Choice] = [Choice(id: answer, label: answer, audioId: "w-" + answer.lowercased(), emoji: nil, correct: true)]
                for w in wrong {
                    qChoices.append(Choice(id: w.text, label: w.text, audioId: "w-" + w.text, emoji: nil, correct: false))
                    graphemes.append(contentsOf: w.graphemes)
                }
                questions.append(StoryQuestion(prompt: "Which of these words did you read in the story?", choices: rng.shuffled(qChoices)))
            }
        }
        return Activity(key: key(type, ctx.unit.id, story.id), type: type, unitId: ctx.unit.id, track: .read,
                        prompt: story.title,
                        spokenPrompt: "It's story time. Let's read together.",
                        audioIds: ["i-story-time"],
                        payload: .story(title: story.title, pages: pages, questions: questions),
                        graphemesUsed: unique(graphemes), trickyUsed: unique(tricky))
    }

    private static func buildFluency(ctx: GenContext, spec: ActivitySpec, rng: inout SeededRNG) -> Activity? {
        let type: ActivityType = .fluency
        var picked: [Word] = []
        var itemKey: String = ""
        var attempt: Int = 0
        while attempt < 4 {
            let focusPick: [Word] = Array(rng.shuffled(ctx.focusMulti).prefix(4))
            var seen: Set<String> = Set(focusPick.map { $0.text.lowercased() })
            let others: [Word] = rng.shuffled(ctx.decodableMulti.filter { !seen.contains($0.text.lowercased()) })
            var words: [Word] = focusPick
            for w in others {
                if words.count >= 6 { break }
                if seen.insert(w.text.lowercased()).inserted { words.append(w) }
            }
            words = rng.shuffled(words)
            picked = words
            itemKey = key(type, ctx.unit.id, words.map { $0.text }.joined(separator: "-"))
            if !spec.excludeKeys.contains(itemKey) { break }
            attempt += 1
        }
        if picked.count < 3 { return nil }
        var graphemes: [String] = []
        for w in picked { graphemes.append(contentsOf: w.graphemes) }
        return Activity(key: itemKey, type: type, unitId: ctx.unit.id, track: .read,
                        prompt: "Read these words at your own pace.",
                        spokenPrompt: "Read these words. Take your time.",
                        audioIds: ["i-read-the-word"],
                        payload: .fluency(words: picked.map { $0.text }, softTargetSeconds: picked.count * 6),
                        graphemesUsed: unique(graphemes), trickyUsed: [])
    }

    // MARK: Simplify and model

    private static func reduceChoices(_ choices: [Choice]) -> [Choice] {
        if choices.count <= 2 { return choices }
        var kept: [Choice] = []
        var haveWrong: Bool = false
        for c in choices {
            if c.correct {
                kept.append(c)
            } else if !haveWrong {
                kept.append(c)
                haveWrong = true
            }
        }
        return kept
    }

    private static func withoutExtraTiles(_ tiles: [String], graphemes: [String]) -> [String] {
        var remaining: [String] = graphemes
        var out: [String] = []
        for t in tiles {
            if let i = remaining.firstIndex(of: t) {
                remaining.remove(at: i)
                out.append(t)
            }
        }
        return out
    }

    /// An easier variant of the same item: fewer choices, no extra tiles, shorter word lists. Key gains "~easy".
    public static func simplify(_ activity: Activity) -> Activity {
        let payload: ActivityPayload
        switch activity.payload {
        case let .choose(choices, target, emoji):
            payload = .choose(choices: reduceChoices(choices), target: target, emoji: emoji)
        case let .blend(graphemes, word, choices, emoji):
            payload = .blend(graphemes: graphemes, word: word, choices: reduceChoices(choices), emoji: emoji)
        case .order:
            payload = activity.payload
        case let .segment(word, graphemes, tiles, emoji):
            payload = .segment(word: word, graphemes: graphemes, tiles: withoutExtraTiles(tiles, graphemes: graphemes), emoji: emoji)
        case let .build(word, graphemes, tiles, emoji):
            payload = .build(word: word, graphemes: graphemes, tiles: withoutExtraTiles(tiles, graphemes: graphemes), emoji: emoji)
        case let .picture(word, choices):
            payload = .picture(word: word, choices: reduceChoices(choices))
        case let .tricky(word, choices):
            payload = .tricky(word: word, choices: reduceChoices(choices))
        case let .sentence(tokens, blankIndex, choices, emoji):
            payload = .sentence(tokens: tokens, blankIndex: blankIndex, choices: reduceChoices(choices), emoji: emoji)
        case let .story(title, pages, questions):
            let easier: [StoryQuestion] = questions.map { StoryQuestion(prompt: $0.prompt, choices: reduceChoices($0.choices)) }
            payload = .story(title: title, pages: pages, questions: easier)
        case let .fluency(words, soft):
            payload = .fluency(words: Array(words.prefix(3)), softTargetSeconds: max(soft, 18))
        }
        let newKey: String = activity.key.hasSuffix("~easy") ? activity.key : activity.key + "~easy"
        return Activity(key: newKey, type: activity.type, unitId: activity.unitId, track: activity.track, prompt: activity.prompt,
                        spokenPrompt: activity.spokenPrompt, audioIds: activity.audioIds, payload: payload,
                        graphemesUsed: activity.graphemesUsed, trickyUsed: activity.trickyUsed)
    }

    /// Narration for a "we do it together" version of the activity (reveals the answer step by step).
    public static func modelledSteps(_ activity: Activity) -> [String] {
        switch activity.payload {
        case let .choose(_, target, _):
            if activity.type == .matchSoundGrapheme {
                return ["Let's look at the letters together: \(target).",
                        "Listen for the sound they make.",
                        "Now we know. Let's choose that sound together."]
            }
            return ["Let's listen to the sound together.",
                    "Now let's look for the letters that make it.",
                    "Here they are: \(target). Let's choose them together."]
        case let .blend(graphemes, word, _, _):
            return ["Let's sound it out together.",
                    graphemes.joined(separator: " ... "),
                    "Now blend the sounds together: \(word).",
                    "Let's choose the word \(word) together."]
        case let .order(graphemes, _, word, _):
            return ["Let's say the word slowly: \(word).",
                    "Listen for each sound: " + graphemes.joined(separator: ", ") + ".",
                    "We choose them in order: " + graphemes.joined(separator: ", then ") + ".",
                    "That makes \(word)."]
        case let .segment(word, graphemes, _, _):
            return ["Let's say the word slowly: \(word).",
                    "Now we stretch it into its sounds: " + graphemes.joined(separator: " ... ") + ".",
                    "Let's choose each sound in order together."]
        case let .build(word, graphemes, _, _):
            return ["Let's say the word slowly: \(word).",
                    "We need these letters in order: " + graphemes.joined(separator: ", then ") + ".",
                    "Let's build \(word) together."]
        case let .picture(word, _):
            return ["Let's sound it out together: \(word).",
                    "Say each sound, then push them together.",
                    "Now let's find the picture for \(word)."]
        case let .tricky(word, _):
            return ["This is a tricky word. We learn it by heart.",
                    "Look at it closely: \(word).",
                    "Say it with me: \(word). Now let's find it."]
        case let .sentence(tokens, blankIndex, choices, _):
            let answer: String = choices.first(where: { $0.correct })?.label ?? ""
            var shown: [String] = tokens
            if blankIndex >= 0 && blankIndex < shown.count { shown[blankIndex] = answer }
            return ["Let's read the sentence together.",
                    shown.joined(separator: " "),
                    "The word that fits is \(answer). Let's choose it together."]
        case let .story(title, _, _):
            return ["Let's read \(title) together.",
                    "We will read one page at a time, nice and slowly.",
                    "Point to each word as we say it."]
        case let .fluency(words, _):
            return ["Let's read these words together, nice and slowly.",
                    words.joined(separator: "   "),
                    "Point to each word as we say it."]
        }
    }
}
