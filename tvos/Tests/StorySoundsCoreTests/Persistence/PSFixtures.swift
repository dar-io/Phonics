import Foundation
@testable import StorySoundsCore

enum PSFixtures {
    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    static func profile(_ id: String = "p1", nickname: String = "Robin") -> LearnerProfile {
        LearnerProfile(id: id, nickname: nickname, createdAt: t0, contentVersion: "0.1.0")
    }

    static func attempt(_ i: Int, correct: Bool = true, unit: String = "g-s", session: String = "s1") -> Attempt {
        Attempt(at: t0.addingTimeInterval(Double(i)), sessionId: session, unitId: unit, track: .recognise,
                activityType: .listenChooseSound, itemKey: "item-\(i)", correct: correct, support: .independent,
                responseMs: 900, chosen: correct ? nil : "z", expected: correct ? nil : "s")
    }

    static func snapshot(id: String = "p1", attempts: Int = 0, sessions: Int = 0, confusions: Int = 0, skills: [SkillState] = []) -> LearnerSnapshot {
        var s = LearnerSnapshot(profile: profile(id))
        s.attempts = (0..<attempts).map { attempt($0) }
        s.sessions = (0..<sessions).map {
            var x = SessionSummary(id: "sess-\($0)", startedAt: t0.addingTimeInterval(Double($0) * 100))
            x.activitiesDone = 10; x.correct = 8; x.unitsPractised = ["g-s", "g-a"]
            return x
        }
        s.confusions = (0..<confusions).map { ConfusionRecord(expected: "e\($0)", chosen: "c\($0)", count: $0 + 1, lastAt: t0) }
        s.skills = skills
        return s
    }

    static func skill(_ unit: String, _ track: Track = .recognise, status: SkillStatus = .learning, attempts: Int = 3) -> SkillState {
        var k = SkillState(unitId: unit, track: track)
        k.status = status; k.attempts = attempts
        return k
    }

    /// Tiny curriculum decoded from JSON so tests do not depend on the bundled file.
    static func curriculum(unitIds: [String], contentVersion: String = "9.9.9") throws -> Curriculum {
        let units = unitIds.enumerated().map { i, id in
            """
            {"id":"\(id)","order":\(i + 1),"phase":2,"stage":"reception","term":"t","phoneme":"/\(id)/","graphemes":["\(id)"],"kind":"single","audioId":"ph-\(id)","pronunciation":"p","prerequisites":[],"exampleWords":[],"trickyWords":[],"misconceptions":[],"source":"inferred"}
            """
        }.joined(separator: ",")
        let json = """
        {"schemaVersion":1,"contentVersion":"\(contentVersion)","units":[\(units)],"words":[],"trickyWords":[],"sentences":[],"stories":[]}
        """
        return try JSONDecoder().decode(Curriculum.self, from: Data(json.utf8))
    }
}
