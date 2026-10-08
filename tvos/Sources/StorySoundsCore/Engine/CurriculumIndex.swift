import Foundation

/// Helpers for the split-digraph convention (`a_e` sits at the vowel; the silent `e` follows the next token).
public enum GraphemeText {
    public static func isSplit(_ token: String) -> Bool {
        let chars: [Character] = Array(token)
        return chars.count == 3 && chars[1] == "_" && chars[2] == "e" && chars[0].isLetter
    }

    /// Joins a grapheme segmentation back to written text. `["c","a_e","k"]` -> "cake".
    /// Returns nil for a dangling or overlapping split digraph.
    public static func join(_ tokens: [String]) -> String? {
        var out: String = ""
        var pendingE: Bool = false
        for t in tokens {
            if isSplit(t) {
                if pendingE { return nil }
                out += String(t.prefix(1))
                pendingE = true
            } else {
                out += t
                if pendingE {
                    out += "e"
                    pendingE = false
                }
            }
        }
        return pendingE ? nil : out
    }
}

/// Read-only lookup tables over a `Curriculum`. Build once, reuse (it is a value type and `Sendable`).
/// Everything here is deterministic: no dictionary/set iteration order leaks into results.
public struct CurriculumIndex: Sendable {
    /// Phase 4 consolidation units list practice clusters, not new graphemes; they do not enter the taught set.
    public static let consolidationUnitIds: Set<String> = ["p4-cvcc", "p4-ccvc", "p4-long"]

    public let curriculum: Curriculum
    /// Units sorted by `order`.
    public let units: [GraphemeUnit]
    public let maxOrder: Int
    /// unit id -> tracks that can actually be practised for it (see `ActivityGenerator.applicableTracks`).
    public private(set) var applicableTracksByUnit: [String: [Track]] = [:]

    private let unitOrders: [Int]
    private let unitPositionById: [String: Int]
    private let unitOrderById: [String: Int]
    private let firstTaught: [String: Int]
    private let taughtLists: [[String]]
    private let taughtSets: [Set<String>]
    private let wordsByKey: [String: Word]
    private let sortedWords: [Word]
    private let sortedWordOrders: [Int]
    private let sentencesById: [String: Sentence]
    private let sentenceUnlockById: [String: Int]
    private let sortedSentences: [Sentence]
    private let sortedSentenceOrders: [Int]
    private let storyUnlockById: [String: Int]
    private let sortedStories: [Story]
    private let sortedStoryOrders: [Int]
    private let trickyByKey: [String: TrickyWord]
    private let phonemeKeysByUnit: [String: Set<String>]
    private let focusByUnit: [String: [Word]]
    private let firstUnitByGrapheme: [String: GraphemeUnit]
    private let confusableByWord: [String: Set<String>]
    private let pictureBySentence: [String: String]

    /// Common homophone groups, used in addition to any `Word.homophones` in the content. Partners must never appear together
    /// as answer and distractor, because a child who reads one of them correctly would be marked wrong for the other.
    public static let builtInHomophoneGroups: [[String]] = [
        ["sea", "see"], ["be", "bee"], ["ate", "eight"], ["to", "too", "two"], ["no", "know"], ["night", "knight"],
        ["write", "right"], ["new", "knew"], ["which", "witch"], ["not", "knot"], ["cent", "sent", "scent"], ["dew", "due"],
        ["fur", "fir"], ["cord", "chord"], ["past", "passed"], ["hear", "here"], ["wood", "would"], ["their", "there"],
        ["bear", "bare"], ["pair", "pear"], ["sun", "son"], ["one", "won"], ["tail", "tale"], ["mail", "male"],
        ["sail", "sale"], ["meet", "meat"], ["read", "reed"], ["road", "rode"], ["rain", "reign"], ["wait", "weight"],
        ["week", "weak"], ["whole", "hole"], ["hi", "high"], ["by", "buy", "bye"], ["for", "four"], ["blue", "blew"],
        ["flour", "flower"], ["grate", "great"], ["nose", "knows"], ["peace", "piece"], ["plain", "plane"],
        ["steel", "steal"], ["toe", "tow"], ["where", "wear"], ["our", "hour"], ["eye", "i"], ["so", "sew"],
        ["deer", "dear"], ["hare", "hair"], ["mane", "main"], ["stair", "stare"], ["tide", "tied"], ["toad", "towed"],
        ["bored", "board"], ["mist", "missed"], ["bean", "been"], ["berry", "bury"], ["brake", "break"], ["ball", "bawl"],
        ["fair", "fare"], ["heal", "heel"], ["horse", "hoarse"], ["lone", "loan"], ["pail", "pale"], ["pause", "paws"],
        ["rose", "rows"], ["seam", "seem"], ["sight", "site"], ["tea", "tee"], ["wade", "weighed"], ["way", "weigh"],
    ]

    public init(_ curriculum: Curriculum) {
        self.curriculum = curriculum
        let consolidation: Set<String> = CurriculumIndex.consolidationUnitIds

        // Units
        let sortedUnits: [GraphemeUnit] = curriculum.units.sorted { $0.order < $1.order }
        self.units = sortedUnits
        self.maxOrder = sortedUnits.last?.order ?? 0
        self.unitOrders = sortedUnits.map { $0.order }
        var positionById: [String: Int] = [:]
        var orderById: [String: Int] = [:]
        for (i, u) in sortedUnits.enumerated() {
            positionById[u.id] = i
            orderById[u.id] = u.order
        }
        self.unitPositionById = positionById
        self.unitOrderById = orderById

        // Taught graphemes, cumulative per unit position.
        var first: [String: Int] = [:]
        var firstUnit: [String: GraphemeUnit] = [:]
        var lists: [[String]] = []
        var sets: [Set<String>] = []
        var curList: [String] = []
        var curSet: Set<String> = []
        for u in sortedUnits {
            if !consolidation.contains(u.id) {
                for g in u.graphemes {
                    if first[g] == nil {
                        first[g] = u.order
                        firstUnit[g] = u
                    }
                    if !curSet.contains(g) {
                        curSet.insert(g)
                        curList.append(g)
                    }
                }
            }
            lists.append(curList)
            sets.append(curSet)
        }
        self.firstTaught = first
        self.firstUnitByGrapheme = firstUnit
        self.taughtLists = lists
        self.taughtSets = sets

        // Tricky words
        var trickyMap: [String: TrickyWord] = [:]
        for t in curriculum.trickyWords {
            let key: String = t.text.lowercased()
            if let existing = trickyMap[key] {
                if t.introducedAtOrder < existing.introducedAtOrder { trickyMap[key] = t }
            } else {
                trickyMap[key] = t
            }
        }
        self.trickyByKey = trickyMap

        // Words
        var byKey: [String: Word] = [:]
        var unlockByKey: [String: Int] = [:]
        var pairs: [(order: Int, offset: Int, word: Word)] = []
        for (i, w) in curriculum.words.enumerated() {
            let key: String = w.text.lowercased()
            if byKey[key] != nil { continue }
            let o: Int = CurriculumIndex.computeUnlock(graphemes: w.graphemes, text: w.text, first: first,
                                                       orderById: orderById, requirements: curriculum.wordRequirements)
            byKey[key] = w
            unlockByKey[key] = o
            if o != Int.max && !w.graphemes.isEmpty {
                pairs.append((order: o, offset: i, word: w))
            }
        }
        pairs.sort { (a, b) -> Bool in
            if a.order != b.order { return a.order < b.order }
            return a.offset < b.offset
        }
        var confusable: [String: Set<String>] = [:]
        func link(_ a: String, _ b: String) {
            let x: String = a.lowercased()
            let y: String = b.lowercased()
            if x == y { return }
            confusable[x, default: []].insert(y)
            confusable[y, default: []].insert(x)
        }
        for group in CurriculumIndex.builtInHomophoneGroups {
            for i in 0..<group.count {
                for j in (i + 1)..<max(i + 1, group.count) { link(group[i], group[j]) }
            }
        }
        for w in curriculum.words {
            for h in (w.homophones ?? []) { link(w.text, h) }
            for h in (w.sameMeaningAs ?? []) { link(w.text, h) }
        }
        self.confusableByWord = confusable
        self.wordsByKey = byKey
        self.sortedWords = pairs.map { $0.word }
        self.sortedWordOrders = pairs.map { $0.order }

        // Sentences
        var sById: [String: Sentence] = [:]
        var sUnlock: [String: Int] = [:]
        var sPairs: [(order: Int, offset: Int, sentence: Sentence)] = []
        for (i, s) in curriculum.sentences.enumerated() {
            var o: Int = 0
            if s.tokens.isEmpty { o = Int.max }
            for token in s.tokens {
                switch token {
                case let .word(text, graphemes):
                    o = max(o, CurriculumIndex.computeUnlock(graphemes: graphemes, text: text, first: first,
                                                             orderById: orderById, requirements: curriculum.wordRequirements))
                case let .tricky(text):
                    if let t = trickyMap[text.lowercased()] {
                        o = max(o, t.introducedAtOrder)
                    } else {
                        o = Int.max
                    }
                }
            }
            if let stored = s.unlockedByOrder { o = max(o, stored) }
            if sById[s.id] == nil {
                sById[s.id] = s
                sUnlock[s.id] = o
                if o != Int.max { sPairs.append((order: o, offset: i, sentence: s)) }
            }
        }
        sPairs.sort { (a, b) -> Bool in
            if a.order != b.order { return a.order < b.order }
            return a.offset < b.offset
        }
        var pictures: [String: String] = [:]
        for s in curriculum.sentences {
            if let e = s.emoji, !e.isEmpty { pictures[s.id] = e }
        }
        for st in curriculum.stories {
            for page in st.pages where page.sentenceIds.count == 1 {
                if let e = page.emoji, !e.isEmpty, let sid = page.sentenceIds.first, pictures[sid] == nil { pictures[sid] = e }
            }
        }
        self.pictureBySentence = pictures
        self.sentencesById = sById
        self.sentenceUnlockById = sUnlock
        self.sortedSentences = sPairs.map { $0.sentence }
        self.sortedSentenceOrders = sPairs.map { $0.order }

        // Stories
        var stUnlock: [String: Int] = [:]
        var stPairs: [(order: Int, offset: Int, story: Story)] = []
        for (i, st) in curriculum.stories.enumerated() {
            var o: Int = 0
            if st.pages.isEmpty { o = Int.max }
            for page in st.pages {
                if page.sentenceIds.isEmpty { o = Int.max }
                for sid in page.sentenceIds {
                    if let su = sUnlock[sid] { o = max(o, su) } else { o = Int.max }
                }
            }
            stUnlock[st.id] = o
            if o != Int.max { stPairs.append((order: o, offset: i, story: st)) }
        }
        stPairs.sort { (a, b) -> Bool in
            if a.order != b.order { return a.order < b.order }
            return a.offset < b.offset
        }
        self.storyUnlockById = stUnlock
        self.sortedStories = stPairs.map { $0.story }
        self.sortedStoryOrders = stPairs.map { $0.order }

        // Phoneme keys
        var pk: [String: Set<String>] = [:]
        for u in sortedUnits { pk[u.id] = CurriculumIndex.parsePhonemeKeys(u.phoneme) }
        self.phonemeKeysByUnit = pk

        // Focus words per unit (words that practise the unit's own sound/spelling).
        var focus: [String: [Word]] = [:]
        let lowerTexts: [String] = curriculum.words.map { $0.text.lowercased() }
        for u in sortedUnits {
            var candidates: [Word] = []
            for t in u.exampleWords {
                if let w = byKey[t.lowercased()] { candidates.append(w) }
            }
            let newGraphemes: [String] = consolidation.contains(u.id) ? [] : u.graphemes.filter { first[$0] == u.order }
            for (wi, w) in curriculum.words.enumerated() {
                var include: Bool = false
                if let reqs = curriculum.wordRequirements[lowerTexts[wi]], reqs.contains(u.id) {
                    include = true
                }
                if !include && !newGraphemes.isEmpty {
                    for g in w.graphemes where newGraphemes.contains(g) {
                        include = true
                        break
                    }
                }
                if include { candidates.append(w) }
            }
            var seen: Set<String> = []
            var list: [Word] = []
            for w in candidates {
                let key: String = w.text.lowercased()
                guard let o = unlockByKey[key], o <= u.order, !w.graphemes.isEmpty else { continue }
                if seen.insert(key).inserted { list.append(w) }
            }
            focus[u.id] = list
        }
        self.focusByUnit = focus

        // All stored properties are initialised; applicability can use the index itself.
        var applicable: [String: [Track]] = [:]
        for u in sortedUnits {
            applicable[u.id] = ActivityGenerator.applicableTracks(index: self, unit: u)
        }
        self.applicableTracksByUnit = applicable
    }

    // MARK: Static helpers

    private static func computeUnlock(graphemes: [String], text: String, first: [String: Int],
                                      orderById: [String: Int], requirements: [String: [String]]) -> Int {
        var o: Int = 0
        for g in graphemes {
            guard let t = first[g] else { return Int.max }
            o = max(o, t)
        }
        if let reqs = requirements[text.lowercased()] {
            for r in reqs {
                guard let ro = orderById[r] else { return Int.max }
                o = max(o, ro)
            }
        }
        return o
    }

    /// "/oo/ (long)" -> ["oo"]; "/oo/ or /yoo/" -> ["oo","yoo"]. Phonemes that sound the same share a key.
    static func parsePhonemeKeys(_ phoneme: String) -> Set<String> {
        let parts: [Substring] = phoneme.split(separator: "/", omittingEmptySubsequences: false)
        var keys: Set<String> = []
        var i: Int = 1
        while i < parts.count {
            var k: String = String(parts[i]).trimmingCharacters(in: .whitespaces).lowercased()
            if k == "er" { k = "ur" }
            if !k.isEmpty { keys.insert(k) }
            i += 2
        }
        if keys.isEmpty { keys.insert(phoneme.lowercased()) }
        return keys
    }

    private static func countAtOrBelow(_ sorted: [Int], _ n: Int) -> Int {
        var lo: Int = 0
        var hi: Int = sorted.count
        while lo < hi {
            let mid: Int = (lo + hi) / 2
            if sorted[mid] <= n { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    // MARK: Units

    public func unit(id: String) -> GraphemeUnit? {
        guard let p = unitPositionById[id] else { return nil }
        return units[p]
    }

    public func unitOrder(id: String) -> Int? { return unitOrderById[id] }

    public func isConsolidation(_ unit: GraphemeUnit) -> Bool {
        return CurriculumIndex.consolidationUnitIds.contains(unit.id)
    }

    /// Units whose order is <= n, in teaching order.
    public func units(upToOrder n: Int) -> [GraphemeUnit] {
        let c: Int = CurriculumIndex.countAtOrBelow(unitOrders, n)
        return Array(units.prefix(c))
    }

    public func phonemeKeys(of unit: GraphemeUnit) -> Set<String> {
        return phonemeKeysByUnit[unit.id] ?? CurriculumIndex.parsePhonemeKeys(unit.phoneme)
    }

    // MARK: Taught graphemes

    public func taughtGraphemes(upToOrder n: Int) -> Set<String> {
        let c: Int = CurriculumIndex.countAtOrBelow(unitOrders, n)
        return c == 0 ? [] : taughtSets[c - 1]
    }

    /// Taught graphemes in teaching order (deterministic; prefer this over iterating the set).
    public func taughtGraphemeList(upToOrder n: Int) -> [String] {
        let c: Int = CurriculumIndex.countAtOrBelow(unitOrders, n)
        return c == 0 ? [] : taughtLists[c - 1]
    }

    /// Resolves a misconception label to taught graphemes. Accepts a grapheme ("d") or a unit key ("oo-short" -> unit g-oo-short).
    public func resolveGraphemes(_ name: String, atOrder n: Int) -> [String] {
        let taught: Set<String> = taughtGraphemes(upToOrder: n)
        var out: [String] = []
        if taught.contains(name) { out.append(name) }
        if let u = unit(id: "g-" + name), u.order <= n, !isConsolidation(u) {
            for g in u.graphemes where taught.contains(g) && !out.contains(g) { out.append(g) }
        }
        return out
    }

    /// Graphemes (from units taught at `n`) that make the same sound as `unit`. Includes the unit's own graphemes.
    public func graphemesSharingSound(with unit: GraphemeUnit, atOrder n: Int) -> Set<String> {
        let keys: Set<String> = phonemeKeys(of: unit)
        var out: Set<String> = Set(unit.graphemes)
        for u in units(upToOrder: n) where !isConsolidation(u) {
            if !phonemeKeys(of: u).isDisjoint(with: keys) {
                for g in u.graphemes { out.insert(g) }
            }
        }
        return out
    }

    /// Audio id of the first taught unit that spells a sound with `grapheme`.
    public func audioId(forGrapheme grapheme: String, atOrder n: Int) -> String? {
        for u in units(upToOrder: n) where !isConsolidation(u) {
            if u.graphemes.contains(grapheme) { return u.audioId }
        }
        return nil
    }

    /// The unit whose sound `grapheme` makes in `word`: the latest unit listed in the word's requirements that teaches the
    /// grapheme (so `o` in "cold" is g-o-oa, `oo` in "book" is g-oo-short), else the lowest-order unit teaching it.
    public func unit(forGrapheme grapheme: String, inWord word: String) -> GraphemeUnit? {
        if let reqs = curriculum.wordRequirements[word.lowercased()] {
            var best: GraphemeUnit? = nil
            for r in reqs {
                guard let u = unit(id: r), !isConsolidation(u), u.graphemes.contains(grapheme) else { continue }
                if let b = best, b.order >= u.order { continue }
                best = u
            }
            if let b = best { return b }
        }
        return firstUnitByGrapheme[grapheme]
    }

    /// Per-word sound for a letter tile (see `unit(forGrapheme:inWord:)`). Prefer this over `audioId(forGrapheme:atOrder:)`
    /// whenever the word is known: the first-taught sound contradicts the word for about 15% of words.
    public func audioId(forGrapheme grapheme: String, inWord word: String) -> String? {
        return unit(forGrapheme: grapheme, inWord: word)?.audioId
    }

    /// Instruction clips ("i-blend") are narration, never the sound of a letter.
    public static func isInstructionAudio(_ audioId: String) -> Bool { return audioId.hasPrefix("i-") }

    /// A unit whose audio is its own sound (not a consolidation unit and not an instruction clip).
    public func hasOwnSound(_ unit: GraphemeUnit) -> Bool {
        return !isConsolidation(unit) && !CurriculumIndex.isInstructionAudio(unit.audioId)
    }

    /// True when the unit's recognition items can offer at most TWO choices (units 1 and 2: only one or two graphemes are
    /// taught). A guess is right half the time or always, so such items are introductions, not evidence.
    public func hasFewChoiceRecognition(unitId: String) -> Bool {
        guard let u = unit(id: unitId), hasOwnSound(u), applicableTracks(forUnit: unitId).contains(.recognise) else { return false }
        return taughtGraphemes(upToOrder: u.order).count < ActivityGenerator.minChoicesForEvidence
    }

    /// Lower-cased words that must not be offered as a distractor for `text`: homophones and same-meaning words
    /// (from `Word.homophones` / `Word.sameMeaningAs` plus the built-in table). Symmetric.
    public func confusableWords(of text: String) -> Set<String> {
        return confusableByWord[text.lowercased()] ?? []
    }

    public func areConfusable(_ a: String, _ b: String) -> Bool {
        return confusableByWord[a.lowercased()]?.contains(b.lowercased()) ?? false
    }

    /// The picture for a sentence: its own emoji, else the emoji of the story page that shows only this sentence.
    public func picture(forSentence sentence: Sentence) -> String? {
        return pictureBySentence[sentence.id]
    }

    public func applicableTracks(forUnit unitId: String) -> [Track] {
        return applicableTracksByUnit[unitId] ?? []
    }

    /// True when every "recognise" item of the unit can only ever offer ONE choice (unit 1: a single grapheme is taught, so
    /// there is nothing to distract with). Such items are introductions, not evidence: the planner presents them as
    /// "we do it together" (modelled) and progression treats the unit as introduced once the learner has met it.
    public func hasOnlyOneChoiceRecognition(unitId: String) -> Bool {
        guard let u = unit(id: unitId), !isConsolidation(u), applicableTracks(forUnit: unitId).contains(.recognise) else { return false }
        return taughtGraphemes(upToOrder: u.order).count <= 1
    }

    // MARK: Words

    public func word(text: String) -> Word? { return wordsByKey[text.lowercased()] }

    /// Lowest unit order at which the word is decodable; Int.max when it uses an untaught grapheme or an unknown unit.
    public func unlockOrder(graphemes: [String], text: String) -> Int {
        return CurriculumIndex.computeUnlock(graphemes: graphemes, text: text, first: firstTaught,
                                             orderById: unitOrderById, requirements: curriculum.wordRequirements)
    }

    public func unlockOrder(forWord word: Word) -> Int {
        return unlockOrder(graphemes: word.graphemes, text: word.text)
    }

    /// Decodable = every grapheme is taught at `n` AND every word-requirement unit has order <= n.
    public func isWordDecodable(_ word: Word, atOrder n: Int) -> Bool {
        return unlockOrder(forWord: word) <= n
    }

    public func isWordDecodable(graphemes: [String], text: String, atOrder n: Int) -> Bool {
        return unlockOrder(graphemes: graphemes, text: text) <= n
    }

    /// Decodable words at `n`, ordered by the order that unlocks them (ties in curriculum order).
    public func decodableWords(atOrder n: Int) -> [Word] {
        let c: Int = CurriculumIndex.countAtOrBelow(sortedWordOrders, n)
        return Array(sortedWords.prefix(c))
    }

    /// Words that practise `unit` itself (its example words, requirement-gated words, words with its new graphemes),
    /// all decodable at the unit's own order and at `n`.
    public func focusWords(forUnit unit: GraphemeUnit, atOrder n: Int) -> [Word] {
        let all: [Word] = focusByUnit[unit.id] ?? []
        return all.filter { unlockOrder(forWord: $0) <= n }
    }

    // MARK: Tricky words

    public func trickyWords(introducedByOrder n: Int) -> [TrickyWord] {
        return curriculum.trickyWords.filter { $0.introducedAtOrder <= n }
    }

    public func isTrickyIntroduced(_ text: String, atOrder n: Int) -> Bool {
        guard let t = trickyByKey[text.lowercased()] else { return false }
        return t.introducedAtOrder <= n
    }

    // MARK: Sentences and stories

    public func sentence(id: String) -> Sentence? { return sentencesById[id] }

    /// Order at which every token of the sentence is available (stored `unlockedByOrder` and recomputed, whichever is higher).
    public func unlockOrder(forSentence sentence: Sentence) -> Int {
        return sentenceUnlockById[sentence.id] ?? Int.max
    }

    public func decodableSentences(atOrder n: Int) -> [Sentence] {
        let c: Int = CurriculumIndex.countAtOrBelow(sortedSentenceOrders, n)
        return Array(sortedSentences.prefix(c))
    }

    public func unlockOrder(forStory story: Story) -> Int {
        return storyUnlockById[story.id] ?? Int.max
    }

    public func decodableStories(atOrder n: Int) -> [Story] {
        let c: Int = CurriculumIndex.countAtOrBelow(sortedStoryOrders, n)
        return Array(sortedStories.prefix(c))
    }
}
