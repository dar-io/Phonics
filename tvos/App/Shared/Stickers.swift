import Foundation
import StorySoundsCore

/// Rewards are for effort, practice and mastery. There is no ranking, no streak and nothing is ever taken away.
struct StickerInfo: Equatable {
    enum Kind { case effort, practice, mastery, welcome }
    let id: String
    let emoji: String
    let title: String
    let kind: Kind
}

enum StickerCatalog {
    static let effortPool: [(emoji: String, title: String)] = [
        ("\u{1F31F}", "Shining Star"), ("\u{1F98B}", "Butterfly"), ("\u{1F308}", "Rainbow"), ("\u{1F344}", "Toadstool"),
        ("\u{1F33B}", "Sunflower"), ("\u{1F41D}", "Busy Bee"), ("\u{1F989}", "Wise Owl"), ("\u{1F422}", "Steady Turtle"),
        ("\u{1F319}", "Crescent Moon"), ("\u{1F3E1}", "Cosy Cottage"), ("\u{1F332}", "Tall Tree"), ("\u{1F438}", "Happy Frog")
    ]
    static let practiceMilestones: [Int] = [1, 3, 5, 10, 20, 30, 50, 75, 100]
    static let practicePool: [(emoji: String, title: String)] = [
        ("\u{1F388}", "First Adventure"), ("\u{1FA81}", "Kite Day"), ("\u{26F5}", "Little Boat"), ("\u{1F3A8}", "Paint Box"),
        ("\u{1F3AA}", "Story Tent"), ("\u{1F680}", "Rocket Ship"), ("\u{1F3F0}", "Story Castle"), ("\u{1F3C6}", "Practice Cup"),
        ("\u{1F451}", "Reading Crown")
    ]
    static let masteryPool: [String] = ["\u{1F4D6}", "\u{1F4DA}", "\u{1F9E9}", "\u{1F514}", "\u{1F9ED}", "\u{1F5DD}", "\u{1F3B5}", "\u{1F36F}"]

    static func info(for id: String, index: CurriculumIndex?) -> StickerInfo {
        if id == "welcome" { return StickerInfo(id: id, emoji: "\u{1F426}", title: "Hello, Wren!", kind: .welcome) }
        if id.hasPrefix("effort-"), let n = Int(id.dropFirst(7)) {
            let p = effortPool[n % effortPool.count]
            return StickerInfo(id: id, emoji: p.emoji, title: p.title, kind: .effort)
        }
        if id.hasPrefix("practice-"), let n = Int(id.dropFirst(9)) {
            let slot = practiceMilestones.firstIndex(of: n) ?? 0
            let p = practicePool[slot % practicePool.count]
            return StickerInfo(id: id, emoji: p.emoji, title: p.title, kind: .practice)
        }
        if id.hasPrefix("mastery-") {
            let unitId = String(id.dropFirst(8))
            let unit = index?.unit(id: unitId)
            let emoji = masteryPool[(unit?.order ?? 0) % masteryPool.count]
            let title = unit.map { "Sound \($0.phoneme)" } ?? "Sound star"
            return StickerInfo(id: id, emoji: emoji, title: title, kind: .mastery)
        }
        return StickerInfo(id: id, emoji: "\u{2B50}", title: "Sticker", kind: .effort)
    }

    /// Stickers earned by one finished (or paused) session. Pure: callers add them to the profile.
    /// - effort: one per session with at least 3 activities (partial sessions count);
    /// - practice: at session-count milestones;
    /// - mastery: one per newly mastered unit.
    static func earned(owned: [String], completedSessionCount: Int, activitiesDone: Int,
                       masteredBefore: Set<String>, masteredAfter: Set<String>) -> [String] {
        var out: [String] = []
        let have = Set(owned)
        if activitiesDone >= 3 {
            let n = owned.filter { $0.hasPrefix("effort-") }.count
            out.append("effort-\(n)")
            let sessions = completedSessionCount + 1
            if practiceMilestones.contains(sessions) {
                let id = "practice-\(sessions)"
                if !have.contains(id) { out.append(id) }
            }
        }
        for unitId in masteredAfter.subtracting(masteredBefore).sorted() {
            let id = "mastery-\(unitId)"
            if !have.contains(id) { out.append(id) }
        }
        return out
    }
}
