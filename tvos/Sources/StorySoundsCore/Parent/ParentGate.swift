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

public enum AdultChallengeKind: String, Equatable, Sendable { case arithmetic, numberWords }

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
    public static func make(seed: UInt64) -> AdultChallenge {
        var rng = SeededGenerator(seed: seed)
        let useWords = Bool.random(using: &rng)
        let prompt: String
        let answer: Int
        let kind: AdultChallengeKind
        if useWords {
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
        var pool = [1, -1, 2, -2, 10, -10, 9, -9, 11, -11, 20, -20].map { answer + $0 }.filter { $0 > 0 && $0 != answer }
        pool.shuffle(using: &rng)
        var chosen: [Int] = []
        for v in pool where !chosen.contains(v) { chosen.append(v); if chosen.count == 3 { break } }
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
public struct GateLockout: Codable, Equatable, Sendable {
    public static let failuresBeforeLock = 3
    public static let baseSeconds: TimeInterval = 30
    public static let maxSeconds: TimeInterval = 900

    public private(set) var failures = 0
    public private(set) var lockRounds = 0
    public private(set) var lockedUntil: Date?
    public init() {}

    public func isLocked(at now: Date) -> Bool { (lockedUntil.map { now < $0 }) ?? false }
    public func remaining(at now: Date) -> TimeInterval { max(0, lockedUntil.map { $0.timeIntervalSince(now) } ?? 0) }

    /// Records a wrong answer. Returns the lock duration if this failure triggered (or we are in) a lockout.
    @discardableResult
    public mutating func recordFailure(at now: Date) -> TimeInterval? {
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

/// Whole parent-gate flow: hold, then an adult question, with lockout. Pure value type driven by UI events.
public struct ParentGateSession: Equatable, Sendable {
    public enum Stage: Equatable, Sendable {
        case hold
        case challenge(AdultChallenge)
        case unlocked
        case lockedOut(until: Date)
    }
    public private(set) var stage: Stage = .hold
    public private(set) var hold: HoldGate
    public private(set) var lockout: GateLockout

    public init(requiredHold: TimeInterval = 3.0, lockout: GateLockout = GateLockout()) {
        self.hold = HoldGate(requiredDuration: requiredHold); self.lockout = lockout
    }

    /// Call when the screen appears and periodically; moves out of `.lockedOut` once the time has passed.
    public mutating func refresh(at now: Date) {
        if lockout.isLocked(at: now), let u = lockout.lockedUntil { stage = .lockedOut(until: u); hold.cancel(); return }
        if case .lockedOut = stage { stage = .hold; hold.cancel() }
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
        if hold.update(at: now) { stage = .challenge(AdultChallengeFactory.make(seed: challengeSeed)) }
    }

    public mutating func answer(optionIndex: Int, at now: Date, nextSeed: UInt64) {
        guard case let .challenge(c) = stage else { return }
        if c.isCorrect(optionIndex: optionIndex) {
            lockout.recordSuccess(); stage = .unlocked
        } else if lockout.recordFailure(at: now) != nil, let u = lockout.lockedUntil {
            stage = .lockedOut(until: u); hold.cancel()
        } else {
            stage = .challenge(AdultChallengeFactory.make(seed: nextSeed))
        }
    }

    /// Re-arms the gate (e.g. when leaving the parent area).
    public mutating func relock() { stage = .hold; hold.cancel() }
}
