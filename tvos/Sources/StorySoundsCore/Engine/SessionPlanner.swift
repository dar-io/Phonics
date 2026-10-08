import Foundation

public struct SessionPlan: Sendable {
    public let id: String
    public let activities: [Activity]
    public let focusUnitId: String?
    /// Parent-readable notes on why the session looks the way it does.
    public let reasons: [String]
    /// Keys of activities to present as "we do it together" (use `ActivityGenerator.modelledSteps`).
    public let modelledKeys: Set<String>
    /// The highest unit order this session draws content from.
    public let knownOrder: Int
    public init(id: String, activities: [Activity], focusUnitId: String?, reasons: [String], modelledKeys: Set<String>, knownOrder: Int) {
        self.id = id
        self.activities = activities
        self.focusUnitId = focusUnitId
        self.reasons = reasons
        self.modelledKeys = modelledKeys
        self.knownOrder = knownOrder
    }
}

/// Extra activities to splice into a running session when a child hits a run of independent misses.
public struct SessionRecovery: Sendable {
    public let activities: [Activity]
    public let modelledKeys: Set<String>
    public let reason: String
}

private struct PlanState {
    let index: CurriculumIndex
    let knownOrder: Int
    let maxRepeats: Int
    var counts: [String: Int] = [:]
    var keys: Set<String> = []
    var typeUse: [ActivityType: Int] = [:]
    var supportCache: [String: [ActivityType]] = [:]
    /// Units a grown-up asked to revisit that lie beyond `knownOrder`: they may use their own order as the known order.
    var aheadAllowed: Set<String> = []

    init(index: CurriculumIndex, knownOrder: Int, maxRepeats: Int) {
        self.index = index
        self.knownOrder = knownOrder
        self.maxRepeats = maxRepeats
    }

    func known(for unit: GraphemeUnit) -> Int {
        return aheadAllowed.contains(unit.id) ? max(knownOrder, unit.order) : knownOrder
    }

    mutating func supported(_ unit: GraphemeUnit) -> [ActivityType] {
        if let c = supportCache[unit.id] { return c }
        let s: [ActivityType] = ActivityGenerator.supportedTypes(index: index, unitId: unit.id, knownOrder: known(for: unit))
        supportCache[unit.id] = s
        return s
    }

    mutating func coreTypes(_ unit: GraphemeUnit, _ track: Track) -> [ActivityType] {
        let sup: [ActivityType] = supported(unit)
        return ActivityGenerator.coreTypes(for: track).filter { sup.contains($0) }
    }

    /// Tries the given types (least used first, ties random unless `ordered`) and returns the first fresh-enough activity.
    mutating func produce(unit: GraphemeUnit, types: [ActivityType], ordered: Bool, rng: inout SeededRNG) -> Activity? {
        if types.isEmpty { return nil }
        var candidates: [ActivityType] = types
        if !ordered {
            let use: [ActivityType: Int] = typeUse
            let shuffled: [ActivityType] = rng.shuffled(types)
            let withOffset: [(offset: Int, type: ActivityType)] = shuffled.enumerated().map { (offset: $0.offset, type: $0.element) }
            candidates = withOffset.sorted { (a, b) -> Bool in
                let ua: Int = use[a.type] ?? 0
                let ub: Int = use[b.type] ?? 0
                if ua != ub { return ua < ub }
                return a.offset < b.offset
            }.map { $0.type }
        }
        for type in candidates {
            let spec: ActivitySpec = ActivitySpec(unitId: unit.id, type: type, knownOrder: known(for: unit), choiceCount: 3, excludeKeys: keys)
            guard let a = ActivityGenerator.generate(curriculum: index.curriculum, index: index, spec: spec, rng: &rng) else { continue }
            if (counts[a.key] ?? 0) >= maxRepeats { continue }
            register(a)
            return a
        }
        return nil
    }

    mutating func register(_ a: Activity) {
        counts[a.key, default: 0] += 1
        keys.insert(a.key)
        typeUse[a.type, default: 0] += 1
    }
}

public enum SessionPlanner {
    /// TV pacing: one activity roughly every 25 seconds.
    public static let secondsPerActivity: Int = 25
    public static let maxRepeatsPerItem: Int = 3
    public static let struggleThreshold: Int = 3

    private struct ReviewCandidate {
        let unit: GraphemeUnit
        let track: Track
    }

    public static func plan(curriculum: Curriculum, snapshot: LearnerSnapshot, now: Date, seed: UInt64, minutes: Int? = nil) -> SessionPlan {
        return plan(index: CurriculumIndex(curriculum), snapshot: snapshot, now: now, seed: seed, minutes: minutes, focusUnitId: nil)
    }

    /// Compact, unique-enough session id. Ids are stored in every skill's `sessionsSeen`, so they are kept short
    /// (about 15 characters) to protect the storage budget: `plan-<unix seconds, base 36>-<seed low bits, base 36>`.
    public static func sessionId(seed: UInt64, now: Date) -> String {
        let secs: UInt64 = UInt64(max(0, Int64(now.timeIntervalSince1970)))
        return "plan-" + String(secs, radix: 36) + "-" + String(seed & 0xFFFF, radix: 36)
    }

    /// Builds a whole session up front: ~40% focus unit, ~40% due review, ~20% mixed, then a gentle story or fluency finish.
    /// `focusUnitId` lets a grown-up pick the unit (e.g. one they unlocked); otherwise `Progression.nextUnit` decides.
    public static func plan(index: CurriculumIndex, snapshot: LearnerSnapshot, now: Date, seed: UInt64,
                            minutes: Int? = nil, focusUnitId: String? = nil) -> SessionPlan {
        let settings: MasterySettings = snapshot.profile.settings.mastery
        let mins: Int = max(1, minutes ?? settings.sessionMinutes)
        let total: Int = max(4, mins * 60 / secondsPerActivity)
        var rng: SeededRNG = SeededRNG(seed: seed, salt: snapshot.profile.id)
        let skills: [String: SkillState] = Progression.skillMap(snapshot)

        // Focus: an explicit unit, else the unit a grown-up unlocked (parent overrides are honoured here), else the natural next unit.
        let focus: GraphemeUnit? = Progression.nextUnit(index: index, snapshot: snapshot, now: now, focusUnitId: focusUnitId)
        let knownOrder: Int = focus?.order ?? index.maxOrder
        var state: PlanState = PlanState(index: index, knownOrder: knownOrder, maxRepeats: maxRepeatsPerItem)
        var reasons: [String] = []

        // A unit a grown-up asked to revisit that lies beyond the focus may still be reviewed (with content up to its own order),
        // provided the learner has already met it.
        var ahead: Set<String> = []
        for id in Progression.revisitUnitIds(snapshot) {
            if let u = index.unit(id: id), u.order > knownOrder, snapshot.skills.contains(where: { $0.unitId == id }) { ahead.insert(id) }
        }
        state.aheadAllowed = ahead

        // Tracks of the focus unit, and which are struggling.
        var focusTracks: [Track] = []
        var struggling: [Track] = []
        if let f = focus {
            focusTracks = index.applicableTracks(forUnit: f.id)
            for t in focusTracks {
                if (skills[Progression.skillKey(f.id, t)]?.struggleStreak ?? 0) >= struggleThreshold { struggling.append(t) }
            }
            if focusUnitId == nil && Progression.overrideFocusUnit(index: index, snapshot: snapshot, now: now)?.id == f.id {
                reasons.append("Focus: \(Progression.displayName(f, index: index)), which a grown-up unlocked.")
            } else {
                reasons.append("Focus: \(Progression.displayName(f, index: index)).")
            }
        } else {
            reasons.append("Every sound so far is secure, so today is review and reading.")
        }

        // Lead-in when the child is struggling: earlier sounds first, then an easier guided version.
        var lead: [Activity] = []
        var modelled: Set<String> = []
        if let f = focus, !struggling.isEmpty {
            let labels: String = struggling.map { Progression.trackLabel($0) }.joined(separator: " and ")
            reasons.append("Stepping back: \(labels) has been tricky, so we start with earlier sounds and an easier guided version.")
            for pid in f.prerequisites.prefix(2) {
                guard let pu = index.unit(id: pid), pu.order <= knownOrder else { continue }
                var tracks: [Track] = Progression.gateTracks(unit: pu, index: index)
                if tracks.isEmpty { tracks = index.applicableTracks(forUnit: pu.id) }
                for t in tracks.prefix(1) {
                    let types: [ActivityType] = state.coreTypes(pu, t)
                    if let a = state.produce(unit: pu, types: types, ordered: false, rng: &rng) { lead.append(a) }
                }
            }
            for t in struggling.prefix(2) {
                let types: [ActivityType] = state.coreTypes(f, t)
                if let base = state.produce(unit: f, types: types, ordered: false, rng: &rng) {
                    let easy: Activity = ActivityGenerator.simplify(base)
                    state.register(easy)
                    modelled.insert(easy.key)
                    lead.append(easy)
                }
            }
        }

        // Ending: story if one is decodable, otherwise fluency.
        let endUnit: GraphemeUnit? = focus ?? index.units.last
        var endTypes: [ActivityType] = []
        if let e = endUnit {
            let sup: [ActivityType] = state.supported(e)
            endTypes = [ActivityType.readStory, ActivityType.fluency].filter { sup.contains($0) }
        }
        let hasEnding: Bool = !endTypes.isEmpty
        let body: Int = max(0, total - (hasEnding ? 1 : 0))
        let remaining: Int = max(0, body - lead.count)

        // Review candidates.
        let candidates: [ReviewCandidate] = reviewCandidates(index: index, snapshot: snapshot, skills: skills, focus: focus,
                                                            knownOrder: knownOrder, ahead: ahead, now: now)
        var focusN: Int = Int((0.4 * Double(remaining)).rounded())
        var reviewN: Int = Int((0.4 * Double(remaining)).rounded())
        var mixedN: Int = remaining - focusN - reviewN
        if focus == nil {
            reviewN += focusN
            focusN = 0
        }
        if candidates.isEmpty {
            if focus != nil { focusN += reviewN } else { mixedN += reviewN }
            reviewN = 0
        }
        if !candidates.isEmpty {
            let due: Int = candidates.count
            reasons.append("Review: \(due) earlier skill\(due == 1 ? "" : "s") ready for a refresher.")
        }

        // Focus items: gate track first (twice) while it is not yet secure, then rotate through the rest.
        var focusItems: [Activity] = []
        if let f = focus, !focusTracks.isEmpty {
            let order: [Track] = focusTrackOrder(unit: f, index: index, tracks: focusTracks, skills: skills, settings: settings)
            var i: Int = 0
            var misses: Int = 0
            let missLimit: Int = focusN * 3 + 3
            while focusItems.count < focusN && misses < missLimit {
                let t: Track = order[i % order.count]
                i += 1
                let types: [ActivityType] = state.coreTypes(f, t)
                if let a = state.produce(unit: f, types: types, ordered: false, rng: &rng) {
                    focusItems.append(a)
                } else {
                    misses += 1
                }
            }
        }

        // Review items.
        var reviewItems: [Activity] = []
        if !candidates.isEmpty {
            var i: Int = 0
            var misses: Int = 0
            let missLimit: Int = reviewN * 3 + 3
            while reviewItems.count < reviewN && misses < missLimit {
                let c: ReviewCandidate = candidates[i % candidates.count]
                i += 1
                let types: [ActivityType] = state.coreTypes(c.unit, c.track)
                if let a = state.produce(unit: c.unit, types: types, ordered: false, rng: &rng) {
                    reviewItems.append(a)
                } else {
                    misses += 1
                }
            }
        }

        // Mixed items.
        var mixedItems: [Activity] = []
        if let mu = focus ?? index.units.last {
            var misses: Int = 0
            let missLimit: Int = mixedN * 2 + 2
            while mixedItems.count < mixedN && misses < missLimit {
                if let a = state.produce(unit: mu, types: [ActivityType.mixedReview], ordered: true, rng: &rng) {
                    mixedItems.append(a)
                } else {
                    misses += 1
                }
            }
        }

        // Top up if some bucket ran dry (small curricula, capped repeats).
        var have: Int = lead.count + focusItems.count + reviewItems.count + mixedItems.count
        var topMisses: Int = 0
        var j: Int = 0
        while have < body && topMisses < 6 {
            var made: Activity? = nil
            if let f = focus, !focusTracks.isEmpty {
                let t: Track = focusTracks[j % focusTracks.count]
                let types: [ActivityType] = state.coreTypes(f, t)
                if let a = state.produce(unit: f, types: types, ordered: false, rng: &rng) {
                    focusItems.append(a)
                    made = a
                }
            }
            if made == nil, let mu = focus ?? index.units.last {
                if let a = state.produce(unit: mu, types: [ActivityType.mixedReview], ordered: true, rng: &rng) {
                    mixedItems.append(a)
                    made = a
                }
            }
            j += 1
            if made == nil { topMisses += 1 } else { have += 1 }
        }

        // Interleave: review, focus, focus, mixed, review, focus, mixed ...
        var result: [Activity] = lead
        let pattern: [Int] = [1, 0, 0, 2, 1, 0, 2]
        var fi: Int = 0
        var ri: Int = 0
        var mi: Int = 0
        var passes: Int = 0
        while (fi < focusItems.count || ri < reviewItems.count || mi < mixedItems.count) && passes < 1000 {
            for p in pattern {
                if p == 0 && fi < focusItems.count {
                    result.append(focusItems[fi]); fi += 1
                } else if p == 1 && ri < reviewItems.count {
                    result.append(reviewItems[ri]); ri += 1
                } else if p == 2 && mi < mixedItems.count {
                    result.append(mixedItems[mi]); mi += 1
                }
            }
            passes += 1
        }

        if hasEnding, let e = endUnit {
            if let a = state.produce(unit: e, types: endTypes, ordered: true, rng: &rng) {
                result.append(a)
                reasons.append("Finishing with \(a.type == .readStory ? "a short story" : "some gentle word reading").")
            }
        }

        // Single-choice items (unit 1) cannot be answered wrongly and two-choice recognition items (unit 2) can be guessed:
        // present them as "we do it together", never as evidence.
        for a in result where ActivityGenerator.isGuessable(a) { modelled.insert(a.key) }

        // `knownOrder` reports the highest unit order the session really draws content from (a revisited unit may lie ahead).
        var usedOrder: Int = knownOrder
        for a in result { usedOrder = max(usedOrder, index.unitOrder(id: a.unitId) ?? 0) }
        let planId: String = sessionId(seed: seed, now: now)
        return SessionPlan(id: planId, activities: result, focusUnitId: focus?.id, reasons: reasons,
                           modelledKeys: modelled, knownOrder: usedOrder)
    }

    /// Order in which to rotate through the focus unit's tracks: the gate track twice first while it is not yet secure,
    /// then tracks that are not secure (lowest score first), then the secure ones.
    private static func focusTrackOrder(unit: GraphemeUnit, index: CurriculumIndex, tracks: [Track],
                                        skills: [String: SkillState], settings: MasterySettings) -> [Track] {
        func score(_ t: Track) -> Double { return skills[Progression.skillKey(unit.id, t)]?.score ?? 0 }
        func secure(_ t: Track) -> Bool {
            guard let s = skills[Progression.skillKey(unit.id, t)] else { return false }
            return Mastery.isSecure(s, settings: settings)
        }
        let sorted: [Track] = tracks.sorted { (a, b) -> Bool in
            let sa: Bool = secure(a)
            let sb: Bool = secure(b)
            if sa != sb { return !sa }
            if score(a) != score(b) { return score(a) < score(b) }
            return a.rawValue < b.rawValue
        }
        var order: [Track] = []
        let gate: [Track] = Progression.gateTracks(unit: unit, index: index)
        if let g = gate.first, tracks.contains(g), !secure(g) {
            order.append(g)
            order.append(g)
            order.append(contentsOf: sorted.filter { $0 != g })
        } else {
            order = sorted
        }
        return order.isEmpty ? tracks : order
    }

    private static func reviewCandidates(index: CurriculumIndex, snapshot: LearnerSnapshot, skills: [String: SkillState],
                                         focus: GraphemeUnit?, knownOrder: Int, ahead: Set<String>, now: Date) -> [ReviewCandidate] {
        var out: [ReviewCandidate] = []
        var seen: Set<String> = []
        func add(_ unit: GraphemeUnit, _ track: Track) {
            if unit.order > knownOrder && !ahead.contains(unit.id) { return }
            if let f = focus, unit.id == f.id { return }
            if !index.applicableTracks(forUnit: unit.id).contains(track) { return }
            if seen.insert(Progression.skillKey(unit.id, track)).inserted { out.append(ReviewCandidate(unit: unit, track: track)) }
        }
        // Grown-up "revisit" requests.
        for id in Progression.revisitUnitIds(snapshot) {
            guard let u = index.unit(id: id) else { continue }
            for t in index.applicableTracks(forUnit: u.id) { add(u, t) }
        }
        // Skills whose review date has passed, most overdue first.
        for s in Scheduler.dueSkills(snapshot: snapshot, now: now) {
            if let u = index.unit(id: s.unitId) { add(u, s.track) }
        }
        // Unfinished skills of earlier units (the unit was passed on its gate track; other tracks still growing).
        if let f = focus {
            let earlier: [SkillState] = snapshot.skills.filter { s in
                guard let o = index.unitOrder(id: s.unitId) else { return false }
                return o < f.order && s.status == .learning
            }
            let sorted: [SkillState] = earlier.sorted { (a, b) -> Bool in
                if a.score != b.score { return a.score < b.score }
                if a.unitId != b.unitId { return a.unitId < b.unitId }
                return a.track.rawValue < b.track.rawValue
            }
            for s in sorted {
                if let u = index.unit(id: s.unitId) { add(u, s.track) }
            }
        }
        return out
    }

    /// Call when a child reaches `struggleThreshold` independent misses in a row mid-session. Returns an easier, guided
    /// version of the same item plus a quick look at the unit's prerequisite, so the session never traps the child.
    public static func recovery(index: CurriculumIndex, snapshot: LearnerSnapshot, activity: Activity, now: Date, seed: UInt64) -> SessionRecovery {
        var rng: SeededRNG = SeededRNG(seed: seed, salt: "recovery|" + activity.key)
        let known: Int = max(index.unitOrder(id: activity.unitId) ?? 0, snapshot.profile.baselinePlacementOrder ?? 0)
        var state: PlanState = PlanState(index: index, knownOrder: known, maxRepeats: maxRepeatsPerItem)
        var acts: [Activity] = []
        var modelled: Set<String> = []
        let easy: Activity = ActivityGenerator.simplify(activity)
        modelled.insert(easy.key)
        acts.append(easy)
        var reason: String = "A gentler, guided version of the same activity."
        if let u = index.unit(id: activity.unitId) {
            for pid in u.prerequisites.prefix(1) {
                guard let pu = index.unit(id: pid) else { continue }
                var tracks: [Track] = Progression.gateTracks(unit: pu, index: index)
                if tracks.isEmpty { tracks = index.applicableTracks(forUnit: pu.id) }
                for t in tracks.prefix(1) {
                    let types: [ActivityType] = state.coreTypes(pu, t)
                    if let a = state.produce(unit: pu, types: types, ordered: false, rng: &rng) {
                        acts.append(a)
                        reason = "A gentler guided version, then a quick look at an earlier sound."
                    }
                }
            }
        }
        for a in acts where ActivityGenerator.isGuessable(a) { modelled.insert(a.key) }
        return SessionRecovery(activities: acts, modelledKeys: modelled, reason: reason)
    }
}

/// Short, game-like placement check. Stops early after two independent misses in a row.
public struct BaselinePlan: Sendable {
    public let id: String
    public let activities: [Activity]
    public let stopAfterConsecutiveMisses: Int
}

public enum Baseline {
    public static let stopAfterConsecutiveMisses: Int = 2
    /// About this many items, spread evenly over the Reception range (roughly one every 3 to 4 units).
    public static let targetItems: Int = 16

    public static func plan(curriculum: Curriculum, seed: UInt64) -> BaselinePlan {
        return plan(index: CurriculumIndex(curriculum), seed: seed)
    }

    /// About sixteen items, each from a different unit, spread evenly across the whole Reception range, easiest first.
    /// Items that cannot be evidence are skipped: units whose recognition offers fewer than three choices (a guess passes),
    /// and units whose "sound" is only an instruction clip.
    public static func plan(index: CurriculumIndex, seed: UInt64) -> BaselinePlan {
        var rng: SeededRNG = SeededRNG(seed: seed, salt: "baseline")
        var eligible: [GraphemeUnit] = index.units.filter { index.hasOwnSound($0) && $0.stage == .reception }
        if eligible.isEmpty { eligible = index.units.filter { index.hasOwnSound($0) } }
        var activities: [Activity] = []
        if !eligible.isEmpty {
            var usedPositions: Set<Int> = []
            let span: Double = Double(eligible.count - 1)
            for n in 0..<targetItems {
                let pos: Int = targetItems > 1 ? Int((Double(n) * span / Double(targetItems - 1)).rounded()) : 0
                if !usedPositions.insert(pos).inserted { continue }
                let unit: GraphemeUnit = eligible[pos]
                let supported: [ActivityType] = ActivityGenerator.supportedTypes(index: index, unitId: unit.id, knownOrder: unit.order)
                var preference: [ActivityType] = [.listenChooseSound, .findGrapheme]
                if n >= 3 {
                    preference = (n % 2 == 1)
                        ? [.blendToWord, .readPickPicture, .listenChooseSound, .findGrapheme]
                        : [.readPickPicture, .blendToWord, .listenChooseSound, .findGrapheme]
                }
                for type in preference where supported.contains(type) {
                    let spec: ActivitySpec = ActivitySpec(unitId: unit.id, type: type, knownOrder: unit.order, choiceCount: 3)
                    if let a = ActivityGenerator.generate(curriculum: index.curriculum, index: index, spec: spec, rng: &rng) {
                        if ActivityGenerator.isGuessable(a) { continue }
                        activities.append(a)
                        break
                    }
                }
            }
        }
        return BaselinePlan(id: "baseline-" + String(seed & 0xFFFFFFFF, radix: 36), activities: activities,
                            stopAfterConsecutiveMisses: stopAfterConsecutiveMisses)
    }

    /// True once the last `stopAfterConsecutiveMisses` EVIDENCE results are all misses. Modelled results (guessable items) are
    /// not evidence and neither extend nor break a run of misses.
    public static func shouldStop(results: [BaselineItemResult]) -> Bool {
        let evidence: [BaselineItemResult] = results.filter { $0.support != .modelled }
        if evidence.count < stopAfterConsecutiveMisses { return false }
        return evidence.suffix(stopAfterConsecutiveMisses).allSatisfy { !($0.correct && $0.support == .independent) }
    }

    public static func score(curriculum: Curriculum, results: [BaselineItemResult], now: Date) -> BaselinePlacement {
        return Progression.placeFromBaseline(curriculum: curriculum, results: results, now: now)
    }

    public static func score(index: CurriculumIndex, results: [BaselineItemResult], now: Date) -> BaselinePlacement {
        return Progression.placeFromBaseline(index: index, results: results, now: now)
    }
}
