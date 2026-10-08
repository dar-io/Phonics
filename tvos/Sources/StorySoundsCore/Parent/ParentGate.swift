import Foundation

/// Press-and-hold model. The UI calls `begin(at:)` on press-down, `progress(at:)` each frame, `cancel()` on release.
/// Holding must be continuous: cancelling resets progress to zero.
public struct HoldGate: Equatable, Sendable {
    public let requiredDuration: TimeInterval
    public private(set) var startedAt: Date?
    public private(set) var isSatisfied = false

    public init(requiredDuration: TimeInterval = 3.0) { self.requiredDuration = max(0.1, requiredDuration) }

    public var isHolding: Bool { startedAt != nil && !isSatisfied }

    public mutating func begin(at now: Date) {
        guard !isSatisfied, startedAt == nil else { return }
        startedAt = now
    }
    public mutating func cancel() { startedAt = nil; isSatisfied = false }

    /// 0...1. Reaching 1 latches `isSatisfied` once `update(at:)` is called.
    public func progress(at now: Date) -> Double {
        if isSatisfied { return 1 }
        guard let s = startedAt else { return 0 }
        let p = now.timeIntervalSince(s) / requiredDuration
        return min(1, max(0, p))
    }

    /// Latches completion; returns whether the hold is complete.
    @discardableResult
    public mutating func update(at now: Date) -> Bool {
        if progress(at: now) >= 1 { isSatisfied = true }
        return isSatisfied
    }
}

/// Small deterministic RNG (SplitMix64) so challenges are reproducible in tests.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public enum AdultChallengeKind: String, Equatable, Sendable { case arithmetic, numberWords, threeStep }

/// A multiple-choice question for adults: answered with the Siri Remote focus/click, no keyboard.
/// Designed so a 4-7 year old cannot answer it by guessing patterns or reading simple words.
public struct AdultChallenge: Equatable, Sendable {
    public let kind: AdultChallengeKind
    public let prompt: String
    public let options: [String]
    public let correctIndex: Int
    public let seed: UInt64
    public func isCorrect(optionIndex: Int) -> Bool { optionIndex == correctIndex }
}

public enum AdultChallengeFactory {
    /// Number of answer choices. A random tap passes one question 1 time in 6; the gate needs two in a row.
    public static let optionCount = 6

    /// `hard == true` builds the 3-step variant used by the "I can't hold the button" route.
    public static func make(seed: UInt64, hard: Bool = false) -> AdultChallenge {
        var rng = SeededGenerator(seed: seed)
        let prompt: String
        let answer: Int
        let kind: AdultChallengeKind
        if hard {
            kind = .threeStep
            let a = Int.random(in: 12...19, using: &rng)
            let b = Int.random(in: 6...9, using: &rng)
            let c = Int.random(in: 11...29, using: &rng)
            let d = Int.random(in: 7...23, using: &rng)
            prompt = "Multiply \(a) by \(b), take away \(c), then add \(d)."
            answer = a * b - c + d
        } else if Bool.random(using: &rng) {
            kind = .numberWords
            let a = Int.random(in: 31...89, using: &rng)
            let b = Int.random(in: 24...76, using: &rng)
            let c = Int.random(in: 5...19, using: &rng)
            prompt = "Add \(numberWords(a)) and \(numberWords(b)), then take away \(numberWords(c))."
            answer = a + b - c
        } else {
            kind = .arithmetic
            let a = Int.random(in: 13...19, using: &rng)
            let b = Int.random(in: 6...9, using: &rng)
            let c = Int.random(in: 11...29, using: &rng)
            prompt = "What is \(a) \u{00D7} \(b) \u{2212} \(c)?"
            answer = a * b - c
        }
        // Distractors: near misses an adult can rule out, all distinct, positive, never equal to the answer.
        var pool = [1, -1, 2, -2, 10, -10, 9, -9, 11, -11, 20, -20, 3, -3].map { answer + $0 }.filter { $0 > 0 && $0 != answer }
        pool.shuffle(using: &rng)
        var chosen: [Int] = []
        for v in pool where !chosen.contains(v) { chosen.append(v); if chosen.count == optionCount - 1 { break } }
        var all = chosen + [answer]
        all.shuffle(using: &rng)
        return AdultChallenge(kind: kind, prompt: prompt, options: all.map(String.init),
                              correctIndex: all.firstIndex(of: answer) ?? 0, seed: seed)
    }

    /// English words for 0...999, e.g. 47 -> "forty-seven".
    public static func numberWords(_ n: Int) -> String {
        let ones = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
                    "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
        let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
        let v = max(0, min(999, n))
        if v < 20 { return ones[v] }
        if v < 100 { return v % 10 == 0 ? tens[v / 10] : tens[v / 10] + "-" + ones[v % 10] }
        let rest = v % 100
        return ones[v / 100] + " hundred" + (rest == 0 ? "" : " and " + numberWords(rest))
    }
}

/// Backoff after repeated wrong answers. Codable so the app may persist it (e.g. in UserDefaults) to survive relaunch.
/// `lockedUntil` is an absolute time. `lastObservedAt` records the latest clock reading seen, so a clock that is set
/// BACKWARDS (to wait out a lock) is detected and the remaining lock time is kept instead of shortened. A clock moved
/// forwards cannot be told apart from time passing (documented limit; tvOS sets the date automatically).
public struct GateLockout: Codable, Equatable, Sendable {
    public static let failuresBeforeLock = 2
    public static let baseSeconds: TimeInterval = 30
    public static let maxSeconds: TimeInterval = 900
    /// Backward steps smaller than this are treated as normal clock adjustment, not a jump.
    public static let clockToleranceSeconds: TimeInterval = 2

    public private(set) var failures = 0
    public private(set) var lockRounds = 0
    public private(set) var lockedUntil: Date?
    public private(set) var lastObservedAt: Date?
    public init() {}

    public func isLocked(at now: Date) -> Bool { (lockedUntil.map { now < $0 }) ?? false }
    public func remaining(at now: Date) -> TimeInterval { max(0, lockedUntil.map { $0.timeIntervalSince(now) } ?? 0) }

    /// Call with each fresh clock reading (the session does this in `refresh`). Keeps the lock through a backwards
    /// clock jump and clamps a lock that is implausibly far in the future (corrupt data or a forward-then-back jump).
    public mutating func observe(at now: Date) {
        if let last = lastObservedAt, now < last.addingTimeInterval(-GateLockout.clockToleranceSeconds) {
            if let until = lockedUntil {
                let left = until.timeIntervalSince(last)
                lockedUntil = left > 0 ? now.addingTimeInterval(left) : nil
            }
            lastObservedAt = now
        } else if lastObservedAt.map({ now > $0 }) ?? true {
            lastObservedAt = now
        }
        if let until = lockedUntil, until.timeIntervalSince(now) > GateLockout.maxSeconds {
            lockedUntil = now.addingTimeInterval(GateLockout.maxSeconds)
        }
    }

    /// Records a wrong answer. Returns the lock duration if this failure triggered (or we are in) a lockout.
    @discardableResult
    public mutating func recordFailure(at now: Date) -> TimeInterval? {
        observe(at: now)
        if isLocked(at: now) { return remaining(at: now) }
        failures += 1
        guard failures >= GateLockout.failuresBeforeLock else { return nil }
        let d = min(GateLockout.maxSeconds, GateLockout.baseSeconds * pow(2, Double(lockRounds)))
        lockRounds += 1
        failures = 0
        lockedUntil = now.addingTimeInterval(d)
        return d
    }
    public mutating func recordSuccess() { failures = 0; lockRounds = 0; lockedUntil = nil }
}

/// Whole parent-gate flow: hold (or the no-hold route), then TWO consecutive adult questions, with lockout.
/// Pure value type driven by UI events.
public struct ParentGateSession: Equatable, Sendable {
    public enum Stage: Equatable, Sendable {
        case hold
        case challenge(AdultChallenge)
        case unlocked
        case lockedOut(until: Date)
    }
    /// Correct answers in a row needed to unlock.
    public static let correctNeeded = 2

    public private(set) var stage: Stage = .hold
    public private(set) var hold: HoldGate
    public private(set) var lockout: GateLockout
    /// Correct answers so far in this attempt (0 or 1 while a question is showing).
    public private(set) var correctStreak = 0
    /// True when the person chose "I can't hold the button": every question is the harder 3-step variant.
    public private(set) var usesHardQuestions = false

    public init(requiredHold: TimeInterval = 3.0, lockout: GateLockout = GateLockout()) {
        self.hold = HoldGate(requiredDuration: requiredHold); self.lockout = lockout
    }

    /// Call when the screen appears and periodically; moves out of `.lockedOut` once the time has passed.
    public mutating func refresh(at now: Date) {
        lockout.observe(at: now)
        if lockout.isLocked(at: now), let u = lockout.lockedUntil {
            stage = .lockedOut(until: u); hold.cancel(); correctStreak = 0; return
        }
        if case .lockedOut = stage { stage = .hold; hold.cancel(); usesHardQuestions = false }
    }

    public mutating func holdBegan(at now: Date) {
        refresh(at: now)
        guard case .hold = stage else { return }
        hold.begin(at: now)
    }
    public mutating func holdCancelled() { if case .hold = stage { hold.cancel() } }

    public mutating func holdTick(at now: Date, challengeSeed: UInt64) {
        refresh(at: now)
        guard case .hold = stage else { return }
        if hold.update(at: now) { correctStreak = 0; stage = .challenge(AdultChallengeFactory.make(seed: challengeSeed)) }
    }

    /// "I can't hold the button": skips the hold but uses the harder 3-step questions (still no keyboard).
    public mutating func startWithoutHold(at now: Date, challengeSeed: UInt64) {
        refresh(at: now)
        guard case .hold = stage else { return }
        hold.cancel()
        usesHardQuestions = true
        correctStreak = 0
        stage = .challenge(AdultChallengeFactory.make(seed: challengeSeed, hard: true))
    }

    public mutating func answer(optionIndex: Int, at now: Date, nextSeed: UInt64) {
        guard case let .challenge(c) = stage else { return }
        lockout.observe(at: now)
        if c.isCorrect(optionIndex: optionIndex) {
            correctStreak += 1
            if correctStreak >= ParentGateSession.correctNeeded {
                lockout.recordSuccess(); stage = .unlocked
            } else {
                stage = .challenge(AdultChallengeFactory.make(seed: nextSeed, hard: usesHardQuestions))
            }
        } else {
            correctStreak = 0
            if lockout.recordFailure(at: now) != nil, let u = lockout.lockedUntil {
                stage = .lockedOut(until: u); hold.cancel()
            } else {
                stage = .challenge(AdultChallengeFactory.make(seed: nextSeed, hard: usesHardQuestions))
            }
        }
    }

    /// Re-arms the gate (e.g. when leaving the parent area).
    public mutating func relock() { stage = .hold; hold.cancel(); correctStreak = 0; usesHardQuestions = false }
}
