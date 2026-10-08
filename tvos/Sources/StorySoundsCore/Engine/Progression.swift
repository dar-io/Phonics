import Foundation

/// One baseline game item's outcome. Only a correct INDEPENDENT answer counts as "known".
public struct BaselineItemResult: Hashable, Sendable {
    public let unitId: String
    public let correct: Bool
    public let support: SupportLevel
    public init(unitId: String, correct: Bool, support: SupportLevel = .independent) {
        self.unitId = unitId
        self.correct = correct
        self.support = support
    }
    /// A guessable item (one or two choices) is never evidence: it is recorded as `.modelled` and ignored by placement.
    public init(activity: Activity, answer: Answer) {
        self.init(unitId: activity.unitId, correct: answer.correct,
                  support: ActivityGenerator.evidenceSupport(for: activity, answered: answer.support))
    }
}

/// Where the baseline places a learner. Units before `placementOrder` get provisional "learning" skills.
public struct BaselinePlacement: Sendable {
    public let placementOrder: Int
    public let placementUnitId: String?
    public let provisionalSkills: [SkillState]
    public init(placementOrder: Int, placementUnitId: String?, provisionalSkills: [SkillState]) {
        self.placementOrder = placementOrder
        self.placementUnitId = placementUnitId
        self.provisionalSkills = provisionalSkills
    }
}

/// Which unit comes next, why units are locked or open, and baseline placement.
/// Parent overrides only change the explanations / selection; they never touch `SkillState`.
public enum Progression {

    // MARK: Lookups

    static func skillKey(_ unitId: String, _ track: Track) -> String { return unitId + "|" + track.rawValue }

    static func skillMap(_ snapshot: LearnerSnapshot) -> [String: SkillState] {
        var m: [String: SkillState] = [:]
        for s in snapshot.skills { m[skillKey(s.unitId, s.track)] = s }
        return m
    }

    /// Latest override per unit (by timestamp; later array position wins ties).
    public static func latestOverrides(_ snapshot: LearnerSnapshot) -> [String: OverrideMode] {
        var latest: [String: ParentOverride] = [:]
        for o in snapshot.profile.overrides {
            if let existing = latest[o.unitId], existing.at > o.at { continue }
            latest[o.unitId] = o
        }
        return latest.mapValues { $0.mode }
    }

    /// The tracks that must be secure for the learner to move on: recognise, or (for units with no sound of their own,
    /// such as the Phase 4 consolidation units) the first practicable track.
    public static func gateTracks(unit: GraphemeUnit, index: CurriculumIndex) -> [Track] {
        let applicable: [Track] = index.applicableTracks(forUnit: unit.id)
        if applicable.contains(.recognise) { return [.recognise] }
        if let first = applicable.first { return [first] }
        return []
    }

    /// Passed for progression purposes: every gate track is secure (or was secure and is only due a refresher).
    /// A unit with nothing practicable never blocks the sequence.
    public static func isUnitSecure(unit: GraphemeUnit, index: CurriculumIndex, skills: [String: SkillState], settings: MasterySettings) -> Bool {
        let gate: [Track] = gateTracks(unit: unit, index: index)
        if gate.isEmpty { return true }
        for t in gate {
            guard let s = skills[skillKey(unit.id, t)] else { return false }
            if Mastery.isEstablished(s, settings: settings) { continue }
            // Units 1 and 2 teach only one or two graphemes, so their recognise items offer one or two choices and can never
            // be independent evidence (a guess passes). Once the learner has met the unit (any attempt, however it was
            // supported) it must not block the sequence.
            if t == .recognise && index.hasFewChoiceRecognition(unitId: unit.id) && s.status != .new { continue }
            return false
        }
        return true
    }

    /// Soft-pass evidence on one skill: enough independent attempts, spread over enough sessions, with a fair score.
    /// This is steady effort, not mastery.
    public static func meetsSoftPass(_ skill: SkillState, settings: MasterySettings) -> Bool {
        if skill.softPassedAt != nil { return true }
        return skill.attempts >= settings.softPassAttempts
            && skill.sessionsSeen.count >= settings.softPassSessions
            && skill.score >= settings.softPassScore
    }

    private static func gatesPassed(unit: GraphemeUnit, index: CurriculumIndex, skills: [String: SkillState],
                                    settings: MasterySettings, allowIntroduction: Bool) -> Bool {
        let gate: [Track] = gateTracks(unit: unit, index: index)
        if gate.isEmpty { return true }
        for t in gate {
            guard let s = skills[skillKey(unit.id, t)] else { return false }
            if Mastery.isEstablished(s, settings: settings) { continue }
            if allowIntroduction && t == .recognise && index.hasFewChoiceRecognition(unitId: unit.id) && s.status != .new { continue }
            if meetsSoftPass(s, settings: settings) { continue }
            return false
        }
        return true
    }

    /// Passed for introducing the next unit: secure, OR soft-passed (every gate track either established or soft-passed).
    /// A child who keeps trying is never trapped on one unit.
    public static func isUnitPassed(unit: GraphemeUnit, index: CurriculumIndex, skills: [String: SkillState], settings: MasterySettings) -> Bool {
        return gatesPassed(unit: unit, index: index, skills: skills, settings: settings, allowIntroduction: true)
    }

    /// Passed only through the soft-pass rule: not secure, so NOT mastered; it stays in review at the shortest interval.
    public static func isUnitSoftPassed(unit: GraphemeUnit, index: CurriculumIndex, skills: [String: SkillState], settings: MasterySettings) -> Bool {
        if isUnitSecure(unit: unit, index: index, skills: skills, settings: settings) { return false }
        return gatesPassed(unit: unit, index: index, skills: skills, settings: settings, allowIntroduction: false)
    }

    /// Mastered = every applicable track is secure right now.
    public static func isUnitMastered(unit: GraphemeUnit, index: CurriculumIndex, skills: [String: SkillState], settings: MasterySettings) -> Bool {
        let tracks: [Track] = index.applicableTracks(forUnit: unit.id)
        if tracks.isEmpty { return false }
        for t in tracks {
            guard let s = skills[skillKey(unit.id, t)], Mastery.isSecure(s, settings: settings) else { return false }
        }
        return true
    }

    // MARK: Wording

    public static func displayName(_ unit: GraphemeUnit, index: CurriculumIndex) -> String {
        if index.isConsolidation(unit) { return unit.phoneme }
        let letters: String = unit.graphemes.map { "'\($0)'" }.joined(separator: " or ")
        return "the sound \(unit.phoneme) (\(letters))"
    }

    public static func trackLabel(_ track: Track) -> String {
        switch track {
        case .recognise: return "recognising the sound"
        case .blend: return "blending sounds into words"
        case .segment: return "splitting words into sounds"
        case .read: return "reading"
        }
    }

    private static func joinNames(_ names: [String]) -> String {
        if names.count <= 1 { return names.first ?? "" }
        if names.count == 2 { return names[0] + " and " + names[1] }
        return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
    }

    // MARK: Explanations

    public static func explainUnits(curriculum: Curriculum, snapshot: LearnerSnapshot, now: Date) -> [UnitExplanation] {
        return explainUnits(index: CurriculumIndex(curriculum), snapshot: snapshot, now: now)
    }

    public static func explainUnits(index: CurriculumIndex, snapshot: LearnerSnapshot, now: Date) -> [UnitExplanation] {
        let settings: MasterySettings = snapshot.profile.settings.mastery
        let skills: [String: SkillState] = skillMap(snapshot)
        let overrides: [String: OverrideMode] = latestOverrides(snapshot)
        let placement: Int? = snapshot.profile.baselinePlacementOrder

        var passed: [String: Bool] = [:]
        var softPassed: [String: Bool] = [:]
        for u in index.units {
            passed[u.id] = isUnitPassed(unit: u, index: index, skills: skills, settings: settings)
            softPassed[u.id] = isUnitSoftPassed(unit: u, index: index, skills: skills, settings: settings)
        }
        func prerequisiteMet(_ id: String) -> Bool {
            if let p = placement, let o = index.unitOrder(id: id), o < p { return true }
            return passed[id] ?? true
        }

        var out: [UnitExplanation] = []
        for u in index.units {
            let name: String = displayName(u, index: index)
            let tracks: [Track] = index.applicableTracks(forUnit: u.id)
            var unitSkills: [SkillState] = []
            var secureTracks: Int = 0
            for t in tracks {
                if let s = skills[skillKey(u.id, t)] {
                    unitSkills.append(s)
                    if Mastery.isSecure(s, settings: settings) { secureTracks += 1 }
                }
            }
            let blocked: [String] = u.prerequisites.filter { !prerequisiteMet($0) }
            let placedPast: Bool = placement.map { u.order < $0 } ?? false
            let overrideMode: OverrideMode? = overrides[u.id]
            let dueSkills: [SkillState] = unitSkills.filter { Scheduler.isDue($0, now: now) && $0.secureAt != nil }
            let hasEvidence: Bool = unitSkills.contains { $0.status != .new || $0.attempts > 0 }
            let allSecure: Bool = !tracks.isEmpty && secureTracks == tracks.count

            var status: UnitStatus
            var reason: String
            var blockedBy: [String] = []

            if !dueSkills.isEmpty {
                status = .reviewDue
                let what: String = joinNames(dueSkills.map { trackLabel($0.track) })
                reason = "Time for a gentle refresher on \(name): \(what)."
            } else if allSecure {
                status = .mastered
                reason = "Secure: \(name) has been shown independently across \(tracks.count) skill\(tracks.count == 1 ? "" : "s")."
            } else if softPassed[u.id] == true {
                status = .inProgress
                reason = "Moving on gently \u{2014} this sound will keep coming back for practice."
            } else if hasEvidence || placedPast {
                status = .inProgress
                if hasEvidence && !placedPast {
                    reason = "Learning \(name): \(secureTracks) of \(tracks.count) skill\(tracks.count == 1 ? "" : "s") secure so far."
                } else {
                    reason = "Placed past \(name) by the starting game, so it will be revisited gently as practice."
                }
            } else if blocked.isEmpty || overrideMode == .unlocked {
                status = .available
                if blocked.isEmpty {
                    reason = "Ready to start: everything \(name) builds on is secure."
                } else {
                    reason = "A grown-up unlocked \(name), so it is open to start."
                }
            } else {
                status = .locked
                blockedBy = blocked
                let names: [String] = blocked.map { id in
                    if let p = index.unit(id: id) { return displayName(p, index: index) }
                    return id
                }
                reason = "Locked until \(joinNames(names)) \(blocked.count == 1 ? "is" : "are") secure."
            }

            if overrideMode == .revisit && status != .locked {
                status = .reviewDue
                blockedBy = []
                reason = "A grown-up asked for \(name) to be practised again."
            }
            out.append(UnitExplanation(unitId: u.id, status: status, reason: reason, blockedBy: blockedBy))
        }
        return out
    }

    // MARK: Next unit

    public static func nextUnit(curriculum: Curriculum, snapshot: LearnerSnapshot, now: Date) -> GraphemeUnit? {
        return nextUnit(index: CurriculumIndex(curriculum), snapshot: snapshot, now: now)
    }

    /// ONE new unit at a time: the earliest not-yet-passed (secure or soft-passed) unit (from the baseline placement onward) whose prerequisites are secure.
    public static func nextUnit(index: CurriculumIndex, snapshot: LearnerSnapshot, now: Date) -> GraphemeUnit? {
        let settings: MasterySettings = snapshot.profile.settings.mastery
        let skills: [String: SkillState] = skillMap(snapshot)
        let placement: Int? = snapshot.profile.baselinePlacementOrder
        var passed: [String: Bool] = [:]
        for u in index.units {
            passed[u.id] = isUnitPassed(unit: u, index: index, skills: skills, settings: settings)
        }
        for u in index.units {
            if let p = placement, u.order < p { continue }
            if passed[u.id] == true { continue }
            var ok: Bool = true
            for pid in u.prerequisites {
                if let p = placement, let o = index.unitOrder(id: pid), o < p { continue }
                if passed[pid] == false { ok = false }
            }
            if ok { return u }
        }
        return nil
    }

    /// After this many sessions that practised the unit, a standing parent "unlock" stops steering the plan, so an old
    /// override can never pin the child to one sound forever.
    public static let overrideSessionCap: Int = 3

    /// The unit a grown-up asked to start (latest `.unlocked` override, newest request first) that is still not secure.
    /// nil when there is none. This is what makes `.unlocked` overrides usable: the planner focuses on it even though
    /// earlier units are still open. Skill states are never touched.
    public static func overrideFocusUnit(index: CurriculumIndex, snapshot: LearnerSnapshot, now: Date) -> GraphemeUnit? {
        let latest: [String: OverrideMode] = latestOverrides(snapshot)
        if latest.isEmpty { return nil }
        let settings: MasterySettings = snapshot.profile.settings.mastery
        let skills: [String: SkillState] = skillMap(snapshot)
        var best: ParentOverride? = nil
        for o in snapshot.profile.overrides {
            guard o.mode == .unlocked, latest[o.unitId] == .unlocked, let unit = index.unit(id: o.unitId) else { continue }
            if isUnitSecure(unit: unit, index: index, skills: skills, settings: settings) { continue }
            let sessionsOnIt: Int = snapshot.sessions.filter { $0.unitsPractised.contains(o.unitId) }.count
            if sessionsOnIt >= overrideSessionCap { continue }
            if let b = best, b.at > o.at { continue }
            best = o
        }
        guard let chosen = best else { return nil }
        return index.unit(id: chosen.unitId)
    }

    /// Focus for the next session: an explicit `focusUnitId` (if it names a unit), else the unit a grown-up unlocked
    /// (see `overrideFocusUnit`), else the natural next unit. The three-argument overload is the natural frontier only.
    public static func nextUnit(index: CurriculumIndex, snapshot: LearnerSnapshot, now: Date, focusUnitId: String?) -> GraphemeUnit? {
        if let fid = focusUnitId, let u = index.unit(id: fid) { return u }
        if let o = overrideFocusUnit(index: index, snapshot: snapshot, now: now) { return o }
        return nextUnit(index: index, snapshot: snapshot, now: now)
    }

    /// Units a grown-up marked for extra practice (latest override wins).
    public static func revisitUnitIds(_ snapshot: LearnerSnapshot) -> [String] {
        let overrides: [String: OverrideMode] = latestOverrides(snapshot)
        var seen: Set<String> = []
        var out: [String] = []
        for o in snapshot.profile.overrides.sorted(by: { $0.at < $1.at }) {
            if overrides[o.unitId] == .revisit && seen.insert(o.unitId).inserted { out.append(o.unitId) }
        }
        return out
    }

    // MARK: Baseline placement

    public static func placeFromBaseline(curriculum: Curriculum, results: [BaselineItemResult], now: Date) -> BaselinePlacement {
        return placeFromBaseline(index: CurriculumIndex(curriculum), results: results, now: now)
    }

    /// How many units before the first sampled miss the learner is placed. A lucky guess above a gap, or a miss that hides a
    /// shaky unit just before it, then costs a few minutes of easy review instead of skipping unknown sounds.
    public static let baselineStepBackUnits: Int = 3

    /// Places the learner conservatively. The first sampled miss marks where knowledge ends; the learner starts
    /// `baselineStepBackUnits` units earlier (never before the first unit). Samples above the first miss are ignored (they
    /// may be guesses). Items answered with help are misses; modelled (guessable) items are not evidence at all. With no miss
    /// the learner starts at the highest sampled unit, provided at least 2 of the last 3 samples are known.
    /// Earlier units get provisional `.learning` skills (never `.secure`: secure needs several sessions and days of evidence).
    public static func placeFromBaseline(index: CurriculumIndex, results: [BaselineItemResult], now: Date) -> BaselinePlacement {
        var verdict: [String: Bool] = [:]
        for r in results {
            guard index.unit(id: r.unitId) != nil else { continue }
            if r.support == .modelled { continue }
            let ok: Bool = r.correct && r.support == .independent
            verdict[r.unitId] = (verdict[r.unitId] ?? true) && ok
        }
        var sampled: [GraphemeUnit] = []
        for (id, _) in verdict {
            if let u = index.unit(id: id) { sampled.append(u) }
        }
        sampled.sort { $0.order < $1.order }

        guard let lastSampled = sampled.last, let firstUnit = index.units.first else {
            return BaselinePlacement(placementOrder: index.units.first?.order ?? 0, placementUnitId: index.units.first?.id, provisionalSkills: [])
        }
        var placement: GraphemeUnit = lastSampled
        if let miss = sampled.first(where: { verdict[$0.id] == false }) {
            let missPos: Int = index.units.firstIndex(where: { $0.id == miss.id }) ?? 0
            placement = index.units[max(0, missPos - baselineStepBackUnits)]
        } else {
            // Nothing missed: trust the top of the range only when the last three samples back it up (2 of 3 known).
            let bracket: [GraphemeUnit] = Array(sampled.suffix(3))
            let known: Int = bracket.filter { verdict[$0.id] == true }.count
            if known < min(2, bracket.count) {
                placement = firstUnit
            }
        }
        if placement.order < firstUnit.order { placement = firstUnit }

        var skills: [SkillState] = []
        for u in index.units where u.order < placement.order {
            for t in gateTracks(unit: u, index: index) {
                var s: SkillState = SkillState(unitId: u.id, track: t)
                s.status = .learning
                s.score = verdict[u.id] == true ? 0.7 : 0.5
                s.lastAttemptAt = now
                s.reviewStage = 0
                let days: Double = 1.0 + Double(u.order % 7)
                s.nextReviewAt = now.addingTimeInterval(days * Scheduler.secondsPerDay)
                skills.append(s)
            }
        }
        return BaselinePlacement(placementOrder: placement.order, placementUnitId: placement.id, provisionalSkills: skills)
    }

    /// Returns a copy of the snapshot with the placement recorded. Existing skill evidence is never overwritten.
    public static func applyPlacement(_ placement: BaselinePlacement, to snapshot: LearnerSnapshot) -> LearnerSnapshot {
        var s: LearnerSnapshot = snapshot
        s.profile.baselineDone = true
        s.profile.baselinePlacementOrder = placement.placementOrder
        for p in placement.provisionalSkills {
            if !s.skills.contains(where: { $0.unitId == p.unitId && $0.track == p.track }) {
                s.skills.append(p)
            }
        }
        return s
    }
}
