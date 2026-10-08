import Foundation

/// Schema version of the Codable curriculum content bundled with the app.
public enum CurriculumSchema { public static let version = 1 }

public enum Stage: String, Codable, Sendable { case reception, year1 }
public enum UnitKind: String, Codable, Sendable { case single, digraph, trigraph, split, alternative }
public enum ContentSource: String, Codable, Sendable { case fetched, inferred }

public struct Misconception: Codable, Hashable, Sendable {
    public let confusedWith: String
    public let guidance: String
}

/// One teaching step: a phoneme and the grapheme(s) that represent it.
public struct GraphemeUnit: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let order: Int
    public let phase: Int
    public let stage: Stage
    public let term: String
    public let phoneme: String
    public let graphemes: [String]
    public let kind: UnitKind
    public let audioId: String
    public let pronunciation: String
    public let prerequisites: [String]
    public let exampleWords: [String]
    public let trickyWords: [String]
    public let misconceptions: [Misconception]
    public let reviewIntervalsDays: [Double]?
    public let source: ContentSource
    public let citation: String?
}

public struct Word: Codable, Hashable, Sendable {
    public let text: String
    public let graphemes: [String]
    public let emoji: String?
    public let pictureLabel: String?
    public let concrete: Bool?
    /// Words that sound the same (sea/see). Never offered together as answer and distractor. Optional in the content.
    public let homophones: [String]?
    /// Words with (nearly) the same meaning, which would also fit a picture or sentence. Optional in the content.
    public let sameMeaningAs: [String]?

    private enum CodingKeys: String, CodingKey { case text, graphemes, emoji, pictureLabel, concrete, homophones, sameMeaningAs }

    public init(text: String, graphemes: [String], emoji: String?, pictureLabel: String?, concrete: Bool?,
                homophones: [String]? = nil, sameMeaningAs: [String]? = nil) {
        self.text = text; self.graphemes = graphemes; self.emoji = emoji; self.pictureLabel = pictureLabel
        self.concrete = concrete; self.homophones = homophones; self.sameMeaningAs = sameMeaningAs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try c.decode(String.self, forKey: .text)
        self.graphemes = try c.decode([String].self, forKey: .graphemes)
        self.emoji = try c.decodeIfPresent(String.self, forKey: .emoji)
        self.pictureLabel = try c.decodeIfPresent(String.self, forKey: .pictureLabel)
        self.concrete = try c.decodeIfPresent(Bool.self, forKey: .concrete)
        self.homophones = Word.flexibleList(c, .homophones)
        self.sameMeaningAs = Word.flexibleList(c, .sameMeaningAs)
    }

    /// Accepts either a list of strings or a single string; anything else (or nothing) is nil, never a decode failure.
    private static func flexibleList(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String]? {
        if let list = try? c.decodeIfPresent([String].self, forKey: key) { return list }
        if let one = try? c.decodeIfPresent(String.self, forKey: key) { return [one] }
        return nil
    }
}

public enum SentenceToken: Codable, Hashable, Sendable {
    case word(text: String, graphemes: [String])
    case tricky(text: String)

    private enum CodingKeys: String, CodingKey { case kind, text, graphemes }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let text = try c.decode(String.self, forKey: .text)
        switch try c.decode(String.self, forKey: .kind) {
        case "tricky": self = .tricky(text: text)
        default: self = .word(text: text, graphemes: try c.decode([String].self, forKey: .graphemes))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .word(text, g): try c.encode("word", forKey: .kind); try c.encode(text, forKey: .text); try c.encode(g, forKey: .graphemes)
        case let .tricky(text): try c.encode("tricky", forKey: .kind); try c.encode(text, forKey: .text)
        }
    }
    public var text: String { switch self { case let .word(t, _), let .tricky(t): return t } }
}

public struct Sentence: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let text: String
    public let tokens: [SentenceToken]
    public let emoji: String?
    public let pictureLabel: String?
    public let unlockedByOrder: Int?
}

public struct StoryPage: Codable, Hashable, Sendable {
    public let sentenceIds: [String]
    public let emoji: String?
    public let pictureLabel: String?
}
public struct Story: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let pages: [StoryPage]
}

public struct TrickyWord: Codable, Hashable, Sendable {
    public let text: String
    public let introducedAtOrder: Int
    public let trickyPart: String?
    public let decodablePartsKnown: Bool?
}

public struct Curriculum: Codable, Sendable {
    public let schemaVersion: Int
    public let contentVersion: String
    public let units: [GraphemeUnit]
    public let words: [Word]
    public let trickyWords: [TrickyWord]
    public let sentences: [Sentence]
    public let stories: [Story]
    /// word text -> extra unit ids that must be taught before the word is decodable (word-requirements.json)
    public var wordRequirements: [String: [String]] = [:]

    private enum CodingKeys: String, CodingKey { case schemaVersion, contentVersion, units, words, trickyWords, sentences, stories }

    public init(schemaVersion: Int, contentVersion: String, units: [GraphemeUnit], words: [Word], trickyWords: [TrickyWord],
                sentences: [Sentence], stories: [Story], wordRequirements: [String: [String]] = [:]) {
        self.schemaVersion = schemaVersion; self.contentVersion = contentVersion; self.units = units; self.words = words
        self.trickyWords = trickyWords; self.sentences = sentences; self.stories = stories; self.wordRequirements = wordRequirements
    }

    public enum LoadError: Error, Equatable { case missingResource(String), unsupportedSchema(Int) }

    /// Loads the curriculum bundled with the package. Throws rather than returning partial content.
    public static func loadBundled() throws -> Curriculum {
        func data(_ name: String) throws -> Data {
            guard let url = Bundle.module.url(forResource: name, withExtension: "json") else { throw LoadError.missingResource(name) }
            return try Data(contentsOf: url)
        }
        var c = try JSONDecoder().decode(Curriculum.self, from: data("curriculum"))
        guard c.schemaVersion == CurriculumSchema.version else { throw LoadError.unsupportedSchema(c.schemaVersion) }
        c.wordRequirements = try JSONDecoder().decode([String: [String]].self, from: data("word-requirements"))
        return c
    }
}

// MARK: Audio manifest (kept separate from activities)
public enum AudioKind: String, Codable, Sendable { case phoneme, word, instruction, sfx }
public enum AudioStatus: String, Codable, Sendable { case placeholder, recorded, verified }
public struct AudioEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: AudioKind
    public let label: String
    public let file: String?
    public let slowFile: String?
    public let status: AudioStatus
    public let note: String?
}
public struct AudioManifest: Codable, Sendable {
    public let version: Int
    public let statement: String
    public let entries: [AudioEntry]
    public static func loadBundled() throws -> AudioManifest {
        guard let url = Bundle.module.url(forResource: "audio-manifest", withExtension: "json") else { throw Curriculum.LoadError.missingResource("audio-manifest") }
        return try JSONDecoder().decode(AudioManifest.self, from: Data(contentsOf: url))
    }
}
