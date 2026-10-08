import Foundation

/// What `SnapshotSanitizer` changed. All zero means the snapshot was already clean.
public struct SanitizeReport: Equatable, Sendable {
    public var droppedSkills = 0
    public var droppedOverrides = 0
    public var droppedAttempts = 0
    public var droppedSessions = 0
    public var droppedConfusions = 0
    public var clampedValues = 0
    public init() {}
    public var isClean: Bool {
        return droppedSkills == 0 && droppedOverrides == 0 && droppedAttempts == 0 && droppedSessions == 0
            && droppedConfusions == 0 && clampedValues == 0
    }
}

/// Makes an untrusted snapshot (iCloud payload, tampered or very old data) safe to store and use:
/// unknown unit ids are dropped, counts and arrays are clamped to the compactor's limits, text is length-limited,
/// settings are forced into sane ranges, future dates are pulled back, and the result is compacted to the byte budget.
/// A snapshot written by a NEWER schema is rejected (never guessed at), as is an unusable profile id.
public enum SnapshotSanitizer {
    public static let maxNicknameLength = 24
    public static let maxProfileIdLength = 100
    public static let maxStickers = 500
    public static let maxStickerIdLength = 64
    public static let maxOverrides = 200
    public static let defaultNickname = "Reader"

    public static func isAcceptableProfileId(_ id: String) -> Bool {
        return !id.isEmpty && id.count <= maxProfileIdLength
    }

    public static func sanitize(_ input: LearnerSnapshot, curriculum: Curriculum?, compactor: SnapshotCompactor = SnapshotCompactor(),
                                now: Date = Date()) throws -> (snapshot: LearnerSnapshot, report: SanitizeReport) {
        if input.profile.schemaVersion > CurriculumSchema.version {
            throw StorageError.newerSchema(found: input.profile.schemaVersion, supported: CurriculumSchema.version)
        }
        guard isAcceptableProfileId(input.profile.id) else { throw StorageError.corrupt("unusable profile id") }

        var report = SanitizeReport()
        var s = input
        let knownUnits: Set<String>? = curriculum.map { c in Set(c.units.map { $0.id }) }
        let maxOrder: Int? = curriculum.map { c in c.units.map { $0.order }.max() ?? 0 }
        let latestAllowed: Date = now.addingTimeInterval(86_400)
        let latestReview: Date = now.addingTimeInterval(400 * 86_400)

        func clampDouble(_ v: Double, _ lo: Double, _ hi: Double, _ fallback: Double) -> Double {
            if v.isNaN || v.isInfinite { report.clampedValues += 1; return fallback }
            let c = min(hi, max(lo, v))
            if c != v { report.clampedValues += 1 }
            return c
        }
        func clampInt(_ v: Int, _ lo: Int, _ hi: Int) -> Int {
            let c = min(hi, max(lo, v))
            if c != v { report.clampedValues += 1 }
            return c
        }
        func clampDate(_ d: Date, latest: Date) -> Date {
            if d.timeIntervalSince1970.isNaN || d > latest { report.clampedValues += 1; return latest == latestAllowed ? now : latest }
            return d
        }
        func cut(_ text: String, _ n: Int) -> String {
            if text.count <= n { return text }
            report.clampedValues += 1
            return String(text.prefix(n))
        }

        // Profile
        var nick = s.profile.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        nick = cut(nick, maxNicknameLength)
        if nick.isEmpty { nick = defaultNickname; report.clampedValues += 1 }
        s.profile.nickname = nick
        s.profile.createdAt = clampDate(s.profile.createdAt, latest: latestAllowed)
        s.profile.contentVersion = cut(s.profile.contentVersion, 40)
        if let o = s.profile.baselinePlacementOrder {
            if o < 1 { s.profile.baselinePlacementOrder = nil; report.clampedValues += 1 }
            else if let m = maxOrder, o > m + 1 { s.profile.baselinePlacementOrder = nil; report.clampedValues += 1 }
        }

        // Settings
        var st = s.profile.settings
        st.narrationVolume = clampDouble(st.narrationVolume, 0, 1, 1.0)
        st.musicVolume = clampDouble(st.musicVolume, 0, 1, 0.4)
        st.effectsVolume = clampDouble(st.effectsVolume, 0, 1, 0.8)
        var m = st.mastery
        m.secureScore = clampDouble(m.secureScore, 0.5, 1.0, 0.85)
        m.minAttempts = clampInt(m.minAttempts, 1, 50)
        m.minSessions = clampInt(m.minSessions, 1, 20)
        m.minDays = clampInt(m.minDays, 1, 30)
        m.minActivityTypes = clampInt(m.minActivityTypes, 1, 6)
        m.maxRecentErrors = clampInt(m.maxRecentErrors, 0, 4)
        m.sessionMinutes = clampInt(m.sessionMinutes, 1, 30)
        if m.reviewLadderDays.isEmpty {
            m.reviewLadderDays = MasterySettings().reviewLadderDays
            report.clampedValues += 1
        } else {
            if m.reviewLadderDays.count > 12 { m.reviewLadderDays = Array(m.reviewLadderDays.prefix(12)); report.clampedValues += 1 }
            m.reviewLadderDays = m.reviewLadderDays.map { clampDouble($0, 0.01, 365, 1) }
        }
        st.mastery = m
        s.profile.settings = st
        let maxStage = max(0, m.reviewLadderDays.count - 1)

        // Stickers and overrides
        var stickers: [String] = []
        var seenStickers = Set<String>()
        for id in s.profile.stickers {
            let t = cut(id, maxStickerIdLength)
            if t.isEmpty || !seenStickers.insert(t).inserted || stickers.count >= maxStickers { report.clampedValues += 1; continue }
            stickers.append(t)
        }
        s.profile.stickers = stickers
        var overrides: [ParentOverride] = []
        for var o in s.profile.overrides {
            if let k = knownUnits, !k.contains(o.unitId) { report.droppedOverrides += 1; continue }
            if overrides.count >= maxOverrides { report.droppedOverrides += 1; continue }
            o.at = clampDate(o.at, latest: latestAllowed)
            overrides.append(o)
        }
        s.profile.overrides = overrides

        // Skills
        var skills: [SkillState] = []
        var index: [String: Int] = [:]
        for original in s.skills {
            if let k = knownUnits, !k.contains(original.unitId) { report.droppedSkills += 1; continue }
            var k = original
            k.score = clampDouble(k.score, 0, 1, 0)
            k.attempts = clampInt(k.attempts, 0, 1_000_000)
            k.independentCorrect = clampInt(k.independentCorrect, 0, k.attempts)
            k.struggleStreak = clampInt(k.struggleStreak, 0, 1_000_000)
            k.reviewStage = clampInt(k.reviewStage, 0, maxStage)
            if k.sessionsSeen.count > compactor.maxSessionsSeenPerSkill {
                k.sessionsSeen = Array(k.sessionsSeen.suffix(compactor.maxSessionsSeenPerSkill)); report.clampedValues += 1
            }
            if k.daysSeen.count > compactor.maxDaysSeenPerSkill {
                k.daysSeen = Array(k.daysSeen.suffix(compactor.maxDaysSeenPerSkill)); report.clampedValues += 1
            }
            k.sessionsSeen = k.sessionsSeen.map { cut($0, 64) }
            k.daysSeen = k.daysSeen.map { cut($0, 16) }
            if k.recentResults.count > Mastery.windowSize {
                k.recentResults = Array(k.recentResults.suffix(Mastery.windowSize)); report.clampedValues += 1
            }
            var types: [ActivityType] = []
            for t in k.activityTypesSeen where !types.contains(t) { types.append(t) }
            k.activityTypesSeen = types
            if let d = k.lastAttemptAt { k.lastAttemptAt = clampDate(d, latest: latestAllowed) }
            if let d = k.secureAt { k.secureAt = clampDate(d, latest: latestAllowed) }
            if let d = k.nextReviewAt { k.nextReviewAt = clampDate(d, latest: latestReview) }
            let key = k.unitId + "|" + k.track.rawValue
            if let i = index[key] {
                skills[i] = k
                report.droppedSkills += 1
            } else {
                index[key] = skills.count
                skills.append(k)
            }
        }
        s.skills = skills

        // Attempts, sessions, confusions
        var attempts: [Attempt] = []
        for original in s.attempts {
            if let k = knownUnits, !k.contains(original.unitId) { report.droppedAttempts += 1; continue }
            var a = original
            a.at = clampDate(a.at, latest: latestAllowed)
            if let ms = a.responseMs, ms < 0 || ms > 3_600_000 { a.responseMs = nil; report.clampedValues += 1 }
            a.itemKey = cut(a.itemKey, 120)
            a.sessionId = cut(a.sessionId, 64)
            if let c = a.chosen { a.chosen = cut(c, 40) }
            if let e = a.expected { a.expected = cut(e, 40) }
            attempts.append(a)
        }
        s.attempts = attempts

        var sessions: [SessionSummary] = []
        var seenSessions = Set<String>()
        for original in s.sessions {
            if !seenSessions.insert(original.id).inserted { report.droppedSessions += 1; continue }
            var x = original
            x.id = cut(x.id, 64)
            x.startedAt = clampDate(x.startedAt, latest: latestAllowed)
            if let e = x.endedAt { x.endedAt = clampDate(e, latest: latestAllowed) }
            x.activitiesDone = clampInt(x.activitiesDone, 0, 10_000)
            x.correct = clampInt(x.correct, 0, x.activitiesDone)
            x.independent = clampInt(x.independent, 0, x.activitiesDone)
            if let k = knownUnits { x.unitsPractised = x.unitsPractised.filter { k.contains($0) } }
            if x.stickersEarned.count > 20 { x.stickersEarned = Array(x.stickersEarned.prefix(20)); report.clampedValues += 1 }
            x.stickersEarned = x.stickersEarned.map { cut($0, maxStickerIdLength) }
            sessions.append(x)
        }
        s.sessions = sessions

        var confusions: [ConfusionRecord] = []
        for original in s.confusions {
            if original.count < 1 { report.droppedConfusions += 1; continue }
            var c = original
            c.count = clampInt(c.count, 1, 100_000)
            c.expected = cut(c.expected, 40)
            c.chosen = cut(c.chosen, 40)
            c.lastAt = clampDate(c.lastAt, latest: latestAllowed)
            confusions.append(c)
        }
        s.confusions = confusions

        if let c = curriculum { s = Migrator.reconcile(s, with: c).snapshot }
        s = compactor.compact(s).snapshot
        return (s, report)
    }
}
