import Foundation

public enum Track: String, Codable, CaseIterable, Sendable { case recognise, blend, segment, read }

public enum ActivityType: String, Codable, CaseIterable, Sendable {
    case listenChooseSound, matchSoundGrapheme, findGrapheme, blendToWord, orderSounds, segmentWord, buildWord
    case readPickPicture, identifyTricky, completeSentence, readStory, fluency, mixedReview
}

public enum SupportLevel: String, Codable, Sendable { case independent, prompted, modelled }

public struct Attempt: Codable, Hashable, Sendable {
    public var at: Date
    public var sessionId: String
    public var unitId: String
    public var track: Track
    public var activityType: ActivityType
    public var itemKey: String
    public var correct: Bool
    public var support: SupportLevel
    public var responseMs: Int?
    public var chosen: String?
    public var expected: String?
    public init(at: Date, sessionId: String, unitId: String, track: Track, activityType: ActivityType, itemKey: String,
                correct: Bool, support: SupportLevel, responseMs: Int? = nil, chosen: String? = nil, expected: String? = nil) {
        self.at = at; self.sessionId = sessionId; self.unitId = unitId; self.track = track; self.activityType = activityType
        self.itemKey = itemKey; self.correct = correct; self.support = support; self.responseMs = responseMs; self.chosen = chosen; self.expected = expected
    }
}

public enum SkillStatus: String, Codable, Sendable { case new, learning, secure, reviewDue }

/// Per unit+track mastery evidence.
public struct SkillState: Codable, Hashable, Sendable {
    public var unitId: String
    public var track: Track
    public var score: Double = 0
    public var attempts: Int = 0
    public var independentCorrect: Int = 0
    public var sessionsSeen: [String] = []
    public var daysSeen: [String] = []        // yyyy-MM-dd
    public var activityTypesSeen: [ActivityType] = []
    public var lastAttemptAt: Date?
    public var recentResults: [Bool] = []     // last 8 independent results
    public var status: SkillStatus = .new
    public var secureAt: Date?
    public var reviewStage: Int = 0
    public var nextReviewAt: Date?
    public var struggleStreak: Int = 0
    /// Set (and kept) once the learner has shown enough steady effort to move on without being secure (see
    /// `MasterySettings.softPassAttempts`). Evidence-driven only; a parent override never writes it.
    public var softPassedAt: Date?
    public init(unitId: String, track: Track) { self.unitId = unitId; self.track = track }
}

public struct ConfusionRecord: Codable, Hashable, Sendable {
    public var expected: String; public var chosen: String; public var count: Int; public var lastAt: Date
    public init(expected: String, chosen: String, count: Int, lastAt: Date) { self.expected = expected; self.chosen = chosen; self.count = count; self.lastAt = lastAt }
}

public struct SessionSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var startedAt: Date
    public var endedAt: Date?
    public var activitiesDone: Int = 0
    public var correct: Int = 0
    public var independent: Int = 0
    public var unitsPractised: [String] = []
    public var stickersEarned: [String] = []
    public var completed: Bool = false
    public init(id: String, startedAt: Date) { self.id = id; self.startedAt = startedAt }
}

public struct MasterySettings: Codable, Hashable, Sendable {
    public var secureScore: Double = 0.85
    public var minAttempts: Int = 6
    public var minSessions: Int = 2
    public var minDays: Int = 2
    public var minActivityTypes: Int = 2
    public var maxRecentErrors: Int = 1
    public var reviewLadderDays: [Double] = [1, 3, 7, 14, 30, 60]
    public var sessionMinutes: Int = 7
    public var useResponseTime: Bool = true
    /// Soft pass: a child who keeps trying is never trapped. A unit counts as passed for introducing the next one after
    /// this many independent attempts, across this many sessions, with at least this score. It is NOT mastery.
    public var softPassAttempts: Int = 12
    public var softPassSessions: Int = 3
    public var softPassScore: Double = 0.6
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case secureScore, minAttempts, minSessions, minDays, minActivityTypes, maxRecentErrors, reviewLadderDays
        case sessionMinutes, useResponseTime, softPassAttempts, softPassSessions, softPassScore
    }

    /// Every key is optional, so settings saved by an older version (without the soft-pass fields) still decode.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        secureScore = try c.decodeIfPresent(Double.self, forKey: .secureScore) ?? secureScore
        minAttempts = try c.decodeIfPresent(Int.self, forKey: .minAttempts) ?? minAttempts
        minSessions = try c.decodeIfPresent(Int.self, forKey: .minSessions) ?? minSessions
        minDays = try c.decodeIfPresent(Int.self, forKey: .minDays) ?? minDays
        minActivityTypes = try c.decodeIfPresent(Int.self, forKey: .minActivityTypes) ?? minActivityTypes
        maxRecentErrors = try c.decodeIfPresent(Int.self, forKey: .maxRecentErrors) ?? maxRecentErrors
        reviewLadderDays = try c.decodeIfPresent([Double].self, forKey: .reviewLadderDays) ?? reviewLadderDays
        sessionMinutes = try c.decodeIfPresent(Int.self, forKey: .sessionMinutes) ?? sessionMinutes
        useResponseTime = try c.decodeIfPresent(Bool.self, forKey: .useResponseTime) ?? useResponseTime
        softPassAttempts = try c.decodeIfPresent(Int.self, forKey: .softPassAttempts) ?? softPassAttempts
        softPassSessions = try c.decodeIfPresent(Int.self, forKey: .softPassSessions) ?? softPassSessions
        softPassScore = try c.decodeIfPresent(Double.self, forKey: .softPassScore) ?? softPassScore
    }
}

public enum OverrideMode: String, Codable, Sendable { case unlocked, revisit }
public struct ParentOverride: Codable, Hashable, Sendable { public var unitId: String; public var mode: OverrideMode; public var at: Date
    public init(unitId: String, mode: OverrideMode, at: Date) { self.unitId = unitId; self.mode = mode; self.at = at } }

public struct LearnerSettings: Codable, Hashable, Sendable {
    public var narrationVolume: Double = 1.0
    public var musicVolume: Double = 0.4
    public var effectsVolume: Double = 0.8
    public var gentleMode: Bool = false          // motion- and sound-sensitive mode
    public var showCaptions: Bool = true
    public var mastery = MasterySettings()
    public init() {}
}

public struct LearnerProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: String                         // stable local id (never a real name)
    public var nickname: String                   // nickname only
    public var createdAt: Date
    public var baselineDone: Bool = false
    public var baselinePlacementOrder: Int?
    public var settings = LearnerSettings()
    public var stickers: [String] = []
    public var overrides: [ParentOverride] = []
    public var schemaVersion: Int = CurriculumSchema.version
    public var contentVersion: String
    public init(id: String, nickname: String, createdAt: Date, contentVersion: String) { self.id = id; self.nickname = nickname; self.createdAt = createdAt; self.contentVersion = contentVersion }
}

/// Everything stored for one learner. Attempts are capped (see Persistence) because tvOS local storage is small.
public struct LearnerSnapshot: Codable, Sendable {
    public var profile: LearnerProfile
    public var skills: [SkillState] = []
    public var confusions: [ConfusionRecord] = []
    public var sessions: [SessionSummary] = []
    public var attempts: [Attempt] = []
    public init(profile: LearnerProfile) { self.profile = profile }
}

public enum UnitStatus: String, Codable, Sendable { case locked, available, inProgress, reviewDue, mastered }
public struct UnitExplanation: Hashable, Sendable { public let unitId: String; public let status: UnitStatus; public let reason: String; public let blockedBy: [String]
    public init(unitId: String, status: UnitStatus, reason: String, blockedBy: [String]) { self.unitId = unitId; self.status = status; self.reason = reason; self.blockedBy = blockedBy } }

// MARK: Activities
public struct Choice: Hashable, Identifiable, Sendable { public let id: String; public let label: String; public let audioId: String?; public let emoji: String?; public let correct: Bool
    public init(id: String, label: String, audioId: String? = nil, emoji: String? = nil, correct: Bool) { self.id = id; self.label = label; self.audioId = audioId; self.emoji = emoji; self.correct = correct } }

public struct StoryQuestion: Hashable, Sendable { public let prompt: String; public let choices: [Choice]
    public init(prompt: String, choices: [Choice]) { self.prompt = prompt; self.choices = choices } }
public struct StoryPageContent: Hashable, Sendable { public let tokens: [(text: String, tricky: Bool)]; public let emoji: String?
    public init(tokens: [(text: String, tricky: Bool)], emoji: String?) { self.tokens = tokens; self.emoji = emoji }
    public static func == (a: Self, b: Self) -> Bool { a.emoji == b.emoji && a.tokens.map(\.text) == b.tokens.map(\.text) }
    public func hash(into h: inout Hasher) { h.combine(emoji); tokens.forEach { h.combine($0.text) } } }

public enum ActivityPayload: Hashable, Sendable {
    case choose(choices: [Choice], target: String, emoji: String?)
    case blend(graphemes: [String], word: String, choices: [Choice], emoji: String?)
    case order(graphemes: [String], tiles: [String], word: String, emoji: String?)
    case segment(word: String, graphemes: [String], tiles: [String], emoji: String?)
    case build(word: String, graphemes: [String], tiles: [String], emoji: String?)
    case picture(word: String, choices: [Choice])
    case tricky(word: String, choices: [Choice])
    case sentence(tokens: [String], blankIndex: Int, choices: [Choice], emoji: String?)
    case story(title: String, pages: [StoryPageContent], questions: [StoryQuestion])
    case fluency(words: [String], softTargetSeconds: Int)
}

public struct Activity: Hashable, Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    public let type: ActivityType
    public let unitId: String
    public let track: Track
    public let prompt: String
    public let spokenPrompt: String
    public let audioIds: [String]
    public let payload: ActivityPayload
    /// Every grapheme/tricky word used; tests verify these are all taught.
    public let graphemesUsed: [String]
    public let trickyUsed: [String]
    public init(key: String, type: ActivityType, unitId: String, track: Track, prompt: String, spokenPrompt: String, audioIds: [String],
                payload: ActivityPayload, graphemesUsed: [String], trickyUsed: [String]) {
        self.key = key; self.type = type; self.unitId = unitId; self.track = track; self.prompt = prompt; self.spokenPrompt = spokenPrompt
        self.audioIds = audioIds; self.payload = payload; self.graphemesUsed = graphemesUsed; self.trickyUsed = trickyUsed
    }
}

public struct Answer: Sendable { public let correct: Bool; public let support: SupportLevel; public let responseMs: Int?; public let chosen: String?; public let expected: String?
    public init(correct: Bool, support: SupportLevel, responseMs: Int? = nil, chosen: String? = nil, expected: String? = nil) { self.correct = correct; self.support = support; self.responseMs = responseMs; self.chosen = chosen; self.expected = expected } }
