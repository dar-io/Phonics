import Foundation

/// Calendar-day key (`yyyy-MM-dd`) used for `SkillState.daysSeen`.
///
/// A "day" is the learner's LOCAL calendar day: the default time zone is the device's current one, so an 8 am and a 6 pm
/// session in Sydney (or two sessions either side of UTC midnight in the US evening) are never mis-counted.
/// Callers (and tests) can inject a time zone or a full `Calendar`.
public enum DayKey {
    /// Fixed UTC zone, for tests and for callers that want the old behaviour.
    public static var utc: TimeZone { return TimeZone(secondsFromGMT: 0) ?? TimeZone.current }

    public static func string(for date: Date, timeZone: TimeZone = TimeZone.current) -> String {
        var cal: Calendar = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return string(for: date, calendar: cal)
    }

    /// Uses the calendar's own time zone. Only the year/month/day components are read.
    public static func string(for date: Date, calendar: Calendar) -> String {
        let c: DateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let y: Int = c.year ?? 1970
        let m: Int = c.month ?? 1
        let d: Int = c.day ?? 1
        let ms: String = m < 10 ? "0\(m)" : "\(m)"
        let ds: String = d < 10 ? "0\(d)" : "\(d)"
        return "\(y)-\(ms)-\(ds)"
    }
}

/// Mastery rules. Pure functions: callers pass `now`.
///
/// Interpretation notes (see also the engineer hand-off):
///  - `SkillState.attempts` counts INDEPENDENT attempts only (the evidence that can make a skill secure).
///    Prompted/modelled attempts are still logged by the caller in `LearnerSnapshot.attempts`.
///  - `sessionsSeen`, `daysSeen`, `activityTypesSeen`, `recentResults` and `score` only ever move on independent attempts.
///    A wrong prompted/modelled attempt can lower `score` by at most `promptedPenalty`.
public enum Mastery {
    /// Weight of the newest independent result in the exponential moving average.
    public static let emaAlpha: Double = 0.3
    /// Starting point of the average before the first independent attempt.
    public static let emaPrior: Double = 0.5
    /// Largest score reduction a prompted/modelled wrong attempt may cause.
    public static let promptedPenalty: Double = 0.02
    /// Size of the recent-results window.
    public static let windowSize: Int = 8
    /// A correct answer faster than this may break a near-tie (never a penalty for being slower).
    public static let fastResponseMs: Int = 3000
    /// How far below `secureScore` a fast answer may still tip a skill that is otherwise clearly secure.
    public static let speedTiebreakMargin: Double = 0.02
    /// Per-skill history caps. They match the storage compactor's defaults, so a skill never grows past what is persisted.
    static let maxSessionsStored: Int = SnapshotCompactor.defaultMaxSessionsSeenPerSkill
    static let maxDaysStored: Int = SnapshotCompactor.defaultMaxDaysSeenPerSkill

    public static func recentErrors(_ skill: SkillState) -> Int {
        return skill.recentResults.suffix(windowSize).filter { !$0 }.count
    }

    /// Pure evidence rules from `MasterySettings` (does not look at `status`).
    public static func meetsEvidence(_ skill: SkillState, settings: MasterySettings) -> Bool {
        if skill.attempts < settings.minAttempts { return false }
        if skill.score < settings.secureScore { return false }
        if skill.sessionsSeen.count < settings.minSessions { return false }
        if skill.daysSeen.count < settings.minDays { return false }
        if skill.activityTypesSeen.count < settings.minActivityTypes { return false }
        if recentErrors(skill) > settings.maxRecentErrors { return false }
        return true
    }

    /// Secure = the persisted status is `.secure`, or a not-yet-promoted skill whose evidence already meets every rule.
    /// A `.reviewDue` skill is not secure until it has recovered.
    public static func isSecure(_ skill: SkillState, settings: MasterySettings) -> Bool {
        switch skill.status {
        case .secure: return true
        case .reviewDue: return false
        case .new, .learning: return meetsEvidence(skill, settings: settings)
        }
    }

    /// "Established" = secure now, or was secure and is merely due for a refresher. Used so a refresher never re-locks later units.
    public static func isEstablished(_ skill: SkillState, settings: MasterySettings) -> Bool {
        if isSecure(skill, settings: settings) { return true }
        return skill.status == .reviewDue && skill.secureAt != nil
    }

    private static func lastResultsAllCorrect(_ skill: SkillState, count: Int) -> Bool {
        let tail: [Bool] = Array(skill.recentResults.suffix(count))
        return tail.count == count && !tail.contains(false)
    }

    /// Folds one attempt into a skill.
    ///
    /// `timeZone` decides which calendar day an attempt belongs to (default: the device's local time zone).
    ///
    /// Recent-error window: when a skill BECOMES secure (first time, or after a refresher recovery) `recentResults` is
    /// cleared. Errors made while still learning therefore never count against a secure skill, and the demotion rule
    /// only sees errors made since the skill last became secure.
    public static func update(skill: SkillState, attempt: Attempt, settings: MasterySettings, now: Date,
                              timeZone: TimeZone = TimeZone.current) -> SkillState {
        var s: SkillState = skill
        s.lastAttemptAt = now

        // Prompted and modelled attempts are help-assisted: never evidence, never a real setback.
        if attempt.support != .independent {
            if !attempt.correct {
                s.score = max(0, s.score - promptedPenalty)
            }
            if s.status == .new { s.status = .learning }
            return s
        }

        let correct: Bool = attempt.correct
        let x: Double = correct ? 1.0 : 0.0
        let base: Double = (s.attempts == 0 && s.score == 0) ? emaPrior : s.score
        let updated: Double = base + emaAlpha * (x - base)
        s.score = min(1.0, max(0.0, updated))
        s.attempts += 1
        if correct {
            s.independentCorrect += 1
            s.struggleStreak = 0
        } else {
            s.struggleStreak += 1
        }
        s.recentResults.append(correct)
        if s.recentResults.count > windowSize {
            s.recentResults.removeFirst(s.recentResults.count - windowSize)
        }
        if !s.sessionsSeen.contains(attempt.sessionId) {
            s.sessionsSeen.append(attempt.sessionId)
            if s.sessionsSeen.count > maxSessionsStored { s.sessionsSeen.removeFirst(s.sessionsSeen.count - maxSessionsStored) }
        }
        let day: String = DayKey.string(for: now, timeZone: timeZone)
        if !s.daysSeen.contains(day) {
            s.daysSeen.append(day)
            if s.daysSeen.count > maxDaysStored { s.daysSeen.removeFirst(s.daysSeen.count - maxDaysStored) }
        }
        if !s.activityTypesSeen.contains(attempt.activityType) {
            s.activityTypesSeen.append(attempt.activityType)
        }

        let errors: Int = recentErrors(s)
        let wasDue: Bool = Scheduler.isDue(skill, now: now)

        switch skill.status {
        case .new, .learning:
            var meets: Bool = meetsEvidence(s, settings: settings)
            if !meets && correct && settings.useResponseTime, let ms = attempt.responseMs, ms >= 0, ms < fastResponseMs {
                // Cautious tiebreaker: speed can only help when every other rule is met, the score is within a hair of
                // the bar, there are no recent errors and the last three answers were all right.
                var probe: SkillState = s
                probe.score = min(1.0, s.score + speedTiebreakMargin)
                if s.score < settings.secureScore && errors == 0 && lastResultsAllCorrect(s, count: 3)
                    && meetsEvidence(probe, settings: settings) {
                    meets = true
                }
            }
            if meets {
                s.status = .secure
                if s.secureAt == nil { s.secureAt = now }
                s.recentResults = []
                s.nextReviewAt = Scheduler.nextReviewAt(stage: s.reviewStage, from: now, settings: settings)
            } else {
                s.status = .learning
            }
        case .secure:
            if correct {
                Scheduler.recordSuccess(&s, wasDue: wasDue, now: now, settings: settings)
            } else {
                // One occasional error never erases progress: stage drops by one and review comes sooner.
                // Repeated errors (2+ in the window) drop the stage to zero and, past the allowance, ask for a review.
                let repeated: Bool = errors >= 2
                if repeated { s.reviewStage = 0 } else { s.reviewStage = max(0, s.reviewStage - 1) }
                s.nextReviewAt = Scheduler.nextReviewAfterError(from: now, settings: settings)
                if repeated && errors > settings.maxRecentErrors { s.status = .reviewDue }
            }
        case .reviewDue:
            if correct {
                if s.score >= settings.secureScore && lastResultsAllCorrect(s, count: 3) {
                    s.status = .secure
                    if s.secureAt == nil { s.secureAt = now }
                    s.recentResults = []
                    s.nextReviewAt = Scheduler.nextReviewAt(stage: s.reviewStage, from: now, settings: settings)
                }
            } else {
                s.reviewStage = 0
                s.nextReviewAt = Scheduler.nextReviewAfterError(from: now, settings: settings)
            }
        }
        return s
    }

    /// Unit mastery = every applicable track is secure.
    public static func isUnitMastered(unitId: String, tracks: [Track], skills: [SkillState], settings: MasterySettings) -> Bool {
        if tracks.isEmpty { return false }
        for t in tracks {
            guard let s = skills.first(where: { $0.unitId == unitId && $0.track == t }) else { return false }
            if !isSecure(s, settings: settings) { return false }
        }
        return true
    }
}

/// Spaced review. Pure: callers pass `now`.
public enum Scheduler {
    public static let secondsPerDay: TimeInterval = 86_400

    public static func intervalDays(forStage stage: Int, settings: MasterySettings) -> Double {
        let ladder: [Double] = settings.reviewLadderDays.isEmpty ? [1] : settings.reviewLadderDays
        let i: Int = min(max(stage, 0), ladder.count - 1)
        return ladder[i]
    }

    public static func nextReviewAt(stage: Int, from now: Date, settings: MasterySettings) -> Date {
        return now.addingTimeInterval(intervalDays(forStage: stage, settings: settings) * secondsPerDay)
    }

    /// After an error the next look comes sooner: at most one day away.
    public static func nextReviewAfterError(from now: Date, settings: MasterySettings) -> Date {
        let first: Double = intervalDays(forStage: 0, settings: settings)
        return now.addingTimeInterval(min(1.0, first) * secondsPerDay)
    }

    /// A skill is due when a review date has passed (or it was demoted to `.reviewDue`).
    public static func isDue(_ skill: SkillState, now: Date) -> Bool {
        if skill.status == .new { return false }
        if skill.status == .reviewDue { return true }
        if let at = skill.nextReviewAt { return at <= now }
        return false
    }

    public static func overdueSeconds(_ skill: SkillState, now: Date) -> TimeInterval {
        let ref: Date = skill.nextReviewAt ?? skill.lastAttemptAt ?? now
        return now.timeIntervalSince(ref)
    }

    /// Correct independent answer on a secure skill. If it was a due review (retention after a delay) the stage advances.
    static func recordSuccess(_ s: inout SkillState, wasDue: Bool, now: Date, settings: MasterySettings) {
        let maxStage: Int = max(0, (settings.reviewLadderDays.isEmpty ? 1 : settings.reviewLadderDays.count) - 1)
        if wasDue {
            s.reviewStage = min(s.reviewStage + 1, maxStage)
            s.nextReviewAt = nextReviewAt(stage: s.reviewStage, from: now, settings: settings)
        } else if s.nextReviewAt == nil {
            s.nextReviewAt = nextReviewAt(stage: s.reviewStage, from: now, settings: settings)
        }
    }

    /// Skills that need a refresher now, most overdue first (ties broken by unit id then track for determinism).
    public static func dueSkills(snapshot: LearnerSnapshot, now: Date) -> [SkillState] {
        let due: [SkillState] = snapshot.skills.filter { isDue($0, now: now) }
        return due.sorted { (a, b) -> Bool in
            let oa: TimeInterval = overdueSeconds(a, now: now)
            let ob: TimeInterval = overdueSeconds(b, now: now)
            if oa != ob { return oa > ob }
            if a.unitId != b.unitId { return a.unitId < b.unitId }
            return a.track.rawValue < b.track.rawValue
        }
    }
}
