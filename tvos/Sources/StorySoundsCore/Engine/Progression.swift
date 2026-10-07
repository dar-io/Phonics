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
    public init(activity: Activity, answer: Answer) {
        self.init(unitId: activity.unitId, correct: answer.correct, support: answer.support)
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
            guard let s = skills[skillKey(unit.id, t)], Mastery.isEstablished(s, settings: settings) else { return false }
        }
        return true
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
        for u in index.units {
            passed[u.id] = isUnitSecure(unit: u, index: index, skills: skills, settings: settings)
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

    /// ONE new unit at a time: the earliest not-yet-secure unit (from the baseline placement onward) whose prerequisites are secure.
    public static func nextUnit(index: CurriculumIndex, snapshot: LearnerSnapshot, now: Date) -> GraphemeUnit? {
        let settings: MasterySettings = snapshot.profile.settings.mastery
        let skills: [String: SkillState] = skillMap(snapshot)
        let placement: Int? = snapshot.profile.baselinePlacementOrder
        var passed: [String: Bool] = [:]
        for u in index.units {
            passed[u.id] = isUnitSecure(unit: u, index: index, skills: skills, settings: settings)
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

    /// Places the learner at the EARLIEST unit not shown to be known, never at the highest unit answered correctly:
    /// the earliest sampled miss, stepped back to any of its direct prerequisites that were not demonstrated.
    /// Earlier units get provisional `.learning` skills (never `.secure`: secure needs several sessions and days of evidence).
    public static func placeFromBaseline(index: CurriculumIndex, results: [BaselineItemResult], now: Date) -> BaselinePlacement {
        var verdict: [String: Bool] = [:]
        for r in results {
            guard index.unit(id: r.unitId) != nil else { continue }
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
            placement = miss
            let lastCorrectBelow: Int = sampled.last(where: { $0.order < miss.order && verdict[$0.id] == true })?.order ?? 0
            for pid in miss.prerequisites {
                if let p = index.unit(id: pid), p.order > lastCorrectBelow, p.order < placement.order {
                    placement = p
                }
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
