import Foundation

/// Keeps a `LearnerSnapshot` inside a byte budget (tvOS UserDefaults is documented as ~500 KB in total).
///
/// Strategy (applied in this order, repeating tighter until it fits):
/// 1. trim per-skill history arrays (sessionsSeen / daysSeen / recentResults);
/// 2. keep the most recent `maxAttempts` attempts, fold dropped wrong answers into `ConfusionRecord`s ONLY when no
///    record for that expected/chosen pair exists yet (SkillState already aggregates the counts, so skills are untouched);
/// 3. keep the newest `maxSessions` sessions;
/// 4. keep the `maxConfusions` most frequent confusions;
/// 5. if still over budget: halve attempts, then sessions, then confusions, then tighten per-skill arrays.
/// Profile, settings, stickers, overrides and skill states are never dropped.
public struct SnapshotCompactor: Sendable {
    public static let defaultBudget = 350_000

    public var byteBudget: Int
    public var maxAttempts: Int
    public var maxSessions: Int
    public var maxConfusions: Int
    public var maxSessionsSeenPerSkill: Int
    public var maxDaysSeenPerSkill: Int

    public init(byteBudget: Int = SnapshotCompactor.defaultBudget, maxAttempts: Int = 500, maxSessions: Int = 100,
                maxConfusions: Int = 100, maxSessionsSeenPerSkill: Int = 50, maxDaysSeenPerSkill: Int = 120) {
        self.byteBudget = byteBudget; self.maxAttempts = maxAttempts; self.maxSessions = maxSessions
        self.maxConfusions = maxConfusions; self.maxSessionsSeenPerSkill = maxSessionsSeenPerSkill
        self.maxDaysSeenPerSkill = maxDaysSeenPerSkill
    }

    public struct Result: Sendable {
        public var snapshot: LearnerSnapshot
        public var encodedBytes: Int
        public var fitsBudget: Bool
        public var attemptsDropped: Int
        public var sessionsDropped: Int
        public var confusionsDropped: Int
    }

    /// Size of the envelope as it would be stored.
    public static func encodedSize(of snapshot: LearnerSnapshot) -> Int {
        let env = SnapshotEnvelope(savedAt: Date(timeIntervalSince1970: 0), snapshot: snapshot)
        return (try? SnapshotCodec.encode(env).count) ?? Int.max
    }

    public func compact(_ input: LearnerSnapshot) -> Result {
        var s = input
        var attemptsDropped = 0, sessionsDropped = 0, confusionsDropped = 0

        // Stable chronological order (oldest first).
        s.attempts = s.attempts.enumerated().sorted { a, b in
            a.element.at == b.element.at ? a.offset < b.offset : a.element.at < b.element.at
        }.map { $0.element }
        s.sessions = s.sessions.enumerated().sorted { a, b in
            a.element.startedAt == b.element.startedAt ? a.offset < b.offset : a.element.startedAt < b.element.startedAt
        }.map { $0.element }

        func trimSkills(sessions: Int, days: Int) {
            for i in s.skills.indices {
                if s.skills[i].sessionsSeen.count > sessions { s.skills[i].sessionsSeen = Array(s.skills[i].sessionsSeen.suffix(sessions)) }
                if s.skills[i].daysSeen.count > days { s.skills[i].daysSeen = Array(s.skills[i].daysSeen.suffix(days)) }
                if s.skills[i].recentResults.count > 8 { s.skills[i].recentResults = Array(s.skills[i].recentResults.suffix(8)) }
            }
        }
        func fold(_ dropped: [Attempt]) {
            for a in dropped where !a.correct {
                guard let e = a.expected, let c = a.chosen else { continue }
                if !s.confusions.contains(where: { $0.expected == e && $0.chosen == c }) {
                    s.confusions.append(ConfusionRecord(expected: e, chosen: c, count: 1, lastAt: a.at))
                }
            }
        }
        func keepAttempts(_ n: Int) {
            guard s.attempts.count > n else { return }
            let cut = s.attempts.count - max(0, n)
            let dropped = Array(s.attempts.prefix(cut))
            s.attempts = Array(s.attempts.suffix(max(0, n)))
            attemptsDropped += dropped.count
            fold(dropped)
        }
        func keepSessions(_ n: Int) {
            guard s.sessions.count > n else { return }
            sessionsDropped += s.sessions.count - max(0, n)
            s.sessions = Array(s.sessions.suffix(max(0, n)))
        }
        func keepConfusions(_ n: Int) {
            guard s.confusions.count > n else { return }
            let sorted = s.confusions.sorted { a, b in
                if a.count != b.count { return a.count > b.count }
                if a.lastAt != b.lastAt { return a.lastAt > b.lastAt }
                return (a.expected + a.chosen) < (b.expected + b.chosen)
            }
            confusionsDropped += sorted.count - max(0, n)
            s.confusions = Array(sorted.prefix(max(0, n)))
        }

        var sessCap = maxSessionsSeenPerSkill, dayCap = maxDaysSeenPerSkill
        trimSkills(sessions: sessCap, days: dayCap)
        keepAttempts(maxAttempts)
        keepSessions(maxSessions)
        keepConfusions(maxConfusions)

        var size = SnapshotCompactor.encodedSize(of: s)
        while size > byteBudget {
            if s.attempts.count > 0 {
                keepAttempts(s.attempts.count / 2)
            } else if s.sessions.count > 0 {
                keepSessions(s.sessions.count / 2)
            } else if s.confusions.count > 0 {
                keepConfusions(s.confusions.count / 2)
            } else if sessCap > 2 || dayCap > 2 {
                sessCap = max(2, sessCap / 2); dayCap = max(2, dayCap / 2)
                trimSkills(sessions: sessCap, days: dayCap)
            } else {
                break
            }
            keepConfusions(maxConfusions)
            size = SnapshotCompactor.encodedSize(of: s)
        }
        return Result(snapshot: s, encodedBytes: size, fitsBudget: size <= byteBudget,
                      attemptsDropped: attemptsDropped, sessionsDropped: sessionsDropped, confusionsDropped: confusionsDropped)
    }
}
