import Foundation

/// Optional extra inputs the Engine can supply (unit statuses, current unit). Without it the report derives
/// statuses from `SkillState` evidence only. Keeps Parent independent of the Engine module.
public struct ReportInputs: Sendable {
    public var unitStatuses: [String: UnitStatus]
    public var currentUnitId: String?
    public init(unitStatuses: [String: UnitStatus] = [:], currentUnitId: String? = nil) {
        self.unitStatuses = unitStatuses; self.currentUnitId = currentUnitId
    }
}

public struct ReportUnitRef: Hashable, Sendable {
    public let id: String
    public let order: Int
    /// e.g. "sh (/sh/)"
    public let label: String
}

public struct ReportSession: Equatable, Sendable {
    public let id: String
    public let startedAt: Date
    public let minutes: Int?
    public let activitiesDone: Int
    public let correct: Int
    public let accuracyPercent: Int?
    public let completed: Bool
}

public struct ReportConfusion: Equatable, Sendable {
    public let expected: String
    public let chosen: String
    public let count: Int
    public let lastAt: Date
}

public struct ParentReport: Sendable {
    public let nickname: String
    public let generatedAt: Date
    public let currentPosition: ReportUnitRef?
    public let masteredUnitIds: Set<String>
    public let developingUnitIds: Set<String>
    public let dueForReviewUnitIds: Set<String>
    /// Ordered by curriculum order.
    public let mastered: [ReportUnitRef]
    public let developing: [ReportUnitRef]
    public let dueForReview: [ReportUnitRef]
    /// Newest first, at most 5.
    public let recentSessions: [ReportSession]
    /// Most frequent first, at most 5.
    public let topConfusions: [ReportConfusion]
    public let totalSessions: Int
    public let stickerCount: Int
    public let suggestedPracticeSteps: [String]
    public var suggestedPractice: String { suggestedPracticeSteps.joined(separator: " ") }

    public static func make(curriculum: Curriculum, snapshot: LearnerSnapshot, now: Date, inputs: ReportInputs? = nil) -> ParentReport {
        let units = curriculum.units.sorted { $0.order < $1.order }
        func ref(_ u: GraphemeUnit) -> ReportUnitRef {
            let g = u.graphemes.joined(separator: ", ")
            return ReportUnitRef(id: u.id, order: u.order, label: g.isEmpty ? u.phoneme : "\(g) (\(u.phoneme))")
        }
        var skillsByUnit: [String: [SkillState]] = [:]
        for s in snapshot.skills where s.attempts > 0 || s.status != .new { skillsByUnit[s.unitId, default: []].append(s) }

        var mastered: [ReportUnitRef] = [], developing: [ReportUnitRef] = [], due: [ReportUnitRef] = []
        for u in units {
            let status: UnitStatus?
            if let given = inputs?.unitStatuses[u.id] {
                status = given
            } else if let skills = skillsByUnit[u.id], !skills.isEmpty {
                let isDue = skills.contains { $0.status == .reviewDue || ($0.status == .secure && ($0.nextReviewAt.map { $0 <= now } ?? false)) }
                if isDue { status = .reviewDue }
                else if skills.allSatisfy({ $0.status == .secure }) { status = .mastered }
                else { status = .inProgress }
            } else {
                status = nil
            }
            switch status {
            case .mastered?: mastered.append(ref(u))
            case .reviewDue?: due.append(ref(u))
            case .inProgress?: developing.append(ref(u))
            default: break
            }
        }

        let masteredIds = Set(mastered.map { $0.id }), dueIds = Set(due.map { $0.id }), devIds = Set(developing.map { $0.id })

        var current: ReportUnitRef?
        if let cid = inputs?.currentUnitId, let u = units.first(where: { $0.id == cid }) {
            current = ref(u)
        } else if let first = developing.first {
            current = first
        } else if let u = units.first(where: { !masteredIds.contains($0.id) && !dueIds.contains($0.id) }) {
            current = ref(u)
        }

        let sessions = snapshot.sessions.sorted { $0.startedAt > $1.startedAt }.prefix(5).map { s -> ReportSession in
            let minutes = s.endedAt.map { max(0, Int(($0.timeIntervalSince(s.startedAt) / 60).rounded())) }
            let acc = s.activitiesDone > 0 ? Int((Double(s.correct) / Double(s.activitiesDone) * 100).rounded()) : nil
            return ReportSession(id: s.id, startedAt: s.startedAt, minutes: minutes, activitiesDone: s.activitiesDone,
                                 correct: s.correct, accuracyPercent: acc, completed: s.completed)
        }

        let confusions = snapshot.confusions.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            if a.lastAt != b.lastAt { return a.lastAt > b.lastAt }
            return (a.expected + a.chosen) < (b.expected + b.chosen)
        }.prefix(5).map { ReportConfusion(expected: $0.expected, chosen: $0.chosen, count: $0.count, lastAt: $0.lastAt) }

        let steps = suggest(current: current, due: due, confusions: Array(confusions), hasHistory: !snapshot.sessions.isEmpty || !skillsByUnit.isEmpty)

        return ParentReport(nickname: snapshot.profile.nickname, generatedAt: now, currentPosition: current,
                            masteredUnitIds: masteredIds, developingUnitIds: devIds, dueForReviewUnitIds: dueIds,
                            mastered: mastered, developing: developing, dueForReview: due,
                            recentSessions: Array(sessions), topConfusions: Array(confusions),
                            totalSessions: snapshot.sessions.count, stickerCount: snapshot.profile.stickers.count,
                            suggestedPracticeSteps: steps)
    }

    private static func suggest(current: ReportUnitRef?, due: [ReportUnitRef], confusions: [ReportConfusion], hasHistory: Bool) -> [String] {
        var steps: [String] = []
        if !hasHistory {
            steps.append("Five-minute start: play one short session together and listen to the first sounds.")
            return steps
        }
        let dueNames = due.prefix(2).map { $0.label }
        if !dueNames.isEmpty { steps.append("About 1 minute: quick review of \(dueNames.joined(separator: " and ")).") }
        if let c = current { steps.append("About 2 minutes: practise \(c.label) with the app, saying the sound with your child.") }
        if let top = confusions.first {
            steps.append("About 1 minute: look at '\(top.expected)' and '\(top.chosen)' side by side and talk about how they differ.")
        } else {
            steps.append("About 1 minute: look for the sound in a picture book or on a sign.")
        }
        steps.append("Finish with a cuddle and a favourite sticker.")
        return steps
    }

    /// Plain-text summary for the parent screen. tvOS has no file sharing, so on-screen text and the opt-in iCloud
    /// backup are the supported "export"; a file export would not be technically appropriate on this platform.
    public func humanReadableSummary(timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB"); f.timeZone = timeZone; f.dateFormat = "d MMM yyyy"
        var lines: [String] = []
        lines.append("Progress for \(nickname) on \(f.string(from: generatedAt))")
        if let c = currentPosition { lines.append("Currently learning: \(c.label)") }
        lines.append("Secure: \(mastered.count) sounds. Still developing: \(developing.count). Due for review: \(dueForReview.count).")
        if !dueForReview.isEmpty { lines.append("Review soon: " + dueForReview.map { $0.label }.joined(separator: ", ")) }
        lines.append("Sessions played: \(totalSessions). Stickers: \(stickerCount).")
        for s in recentSessions {
            var l = "\(f.string(from: s.startedAt)): \(s.activitiesDone) activities"
            if let a = s.accuracyPercent { l += ", \(a)% correct" }
            if let m = s.minutes { l += ", about \(m) min" }
            lines.append(l)
        }
        if !topConfusions.isEmpty {
            lines.append("Often mixed up: " + topConfusions.map { "'\($0.chosen)' chosen instead of '\($0.expected)' (\($0.count) times)" }.joined(separator: "; "))
        }
        lines.append("Idea for five minutes: " + suggestedPractice)
        lines.append("This app is not approved or endorsed by Little Wandle or any publisher.")
        return lines.joined(separator: "\n")
    }
}
