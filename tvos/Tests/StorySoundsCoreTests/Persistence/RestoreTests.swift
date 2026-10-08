import XCTest
@testable import StorySoundsCore

/// Forwards to an in-memory store but makes one profile's save fail (to prove partial restores roll back).
final class FailingSaveStore: LearnerStore, @unchecked Sendable {
    let inner = InMemoryLearnerStore()
    var failOnId: String?
    func load(profileId: String) throws -> LearnerSnapshot? { try inner.load(profileId: profileId) }
    func save(_ snapshot: LearnerSnapshot) throws {
        if snapshot.profile.id == failOnId { throw StorageError.writeFailed(key: "boom") }
        try inner.save(snapshot)
    }
    func delete(profileId: String) throws { try inner.delete(profileId: profileId) }
    func listProfileIds() throws -> [String] { try inner.listProfileIds() }
    func deleteAll() throws { try inner.deleteAll() }
    func loadStored(profileId: String) throws -> StoredSnapshot? { try inner.loadStored(profileId: profileId) }
    func activeProfileId() throws -> String? { try inner.activeProfileId() }
    func setActiveProfileId(_ id: String?) throws { try inner.setActiveProfileId(id) }
}

final class RestoreTests: XCTestCase {
    private func payload(_ snaps: [LearnerSnapshot]) -> BackupPayload { BackupPayload(createdAt: PSFixtures.t0, snapshots: snaps) }
    private let now = PSFixtures.t0.addingTimeInterval(10 * 86_400)

    func testRestoreReturnsWrittenIdsAndTheRestoredProfileBecomesActive() throws {
        // The new Apple TV already onboarded a fresh profile "fresh"; the backup holds "child".
        let store = InMemoryLearnerStore()
        try store.save(PSFixtures.snapshot(id: "fresh"))
        try store.setActiveProfileId("fresh")
        let out = try BackupRestoration.restore(payload([PSFixtures.snapshot(id: "child", attempts: 7)]), to: store, curriculum: nil, now: now)
        XCTAssertEqual(out.writtenIds, ["child"])
        XCTAssertEqual(out.activeProfileId, "child")
        XCTAssertTrue(out.activePointerSet)
        XCTAssertEqual(try store.activeProfileId(), "child")
        XCTAssertEqual(try store.load(profileId: "child")?.attempts.count, 7)
        XCTAssertEqual(try store.load(profileId: "fresh")?.profile.id, "fresh", "the other profile is not deleted")
    }

    func testActiveIsTheProfileWithTheNewestActivity() throws {
        var older = PSFixtures.snapshot(id: "older", attempts: 3)
        older.attempts = older.attempts.map { var a = $0; a.at = PSFixtures.t0; return a }
        var newer = PSFixtures.snapshot(id: "newer", attempts: 3)
        newer.attempts = newer.attempts.map { var a = $0; a.at = PSFixtures.t0.addingTimeInterval(5 * 86_400); return a }
        let out = try BackupRestoration.restore(payload([older, newer]), to: InMemoryLearnerStore(), curriculum: nil, now: now)
        XCTAssertEqual(out.activeProfileId, "newer")
        XCTAssertEqual(Set(out.writtenIds), ["newer", "older"])
    }

    func testApplyStillReturnsWrittenIdsAndHonoursOverwriteFlag() throws {
        let store = InMemoryLearnerStore()
        try store.save(PSFixtures.snapshot(id: "a", attempts: 1))
        let kept = try BackupRestoration.apply(payload([PSFixtures.snapshot(id: "a", attempts: 9)]), to: store, curriculum: nil)
        XCTAssertEqual(kept, [])
        XCTAssertEqual(try store.load(profileId: "a")?.attempts.count, 1)
        let over = try BackupRestoration.apply(payload([PSFixtures.snapshot(id: "a", attempts: 9)]), to: store, curriculum: nil, overwrite: true)
        XCTAssertEqual(over, ["a"])
        XCTAssertEqual(try store.load(profileId: "a")?.attempts.count, 9)
    }

    func testSkippedProfilesAreReported() throws {
        let store = InMemoryLearnerStore()
        try store.save(PSFixtures.snapshot(id: "have"))
        let out = try BackupRestoration.restore(payload([
            PSFixtures.snapshot(id: "have"), PSFixtures.snapshot(id: "dup"), PSFixtures.snapshot(id: "dup"), PSFixtures.snapshot(id: ""),
        ]), to: store, curriculum: nil, now: now)
        XCTAssertEqual(out.writtenIds, ["dup"])
        XCTAssertEqual(out.skipped.map { $0.reason }, [.existingKept, .duplicateInPayload, .invalidId])
    }

    // MARK: Sanitising

    func testUnknownUnitsAreDroppedEverywhere() throws {
        let cur = try PSFixtures.curriculum(unitIds: ["g-s", "g-a"])
        var s = PSFixtures.snapshot(id: "p", attempts: 4)
        s.attempts[0].unitId = "g-gone"
        s.skills = [PSFixtures.skill("g-s"), PSFixtures.skill("g-gone"), PSFixtures.skill("g-a", .blend)]
        s.profile.overrides = [ParentOverride(unitId: "g-gone", mode: .unlocked, at: PSFixtures.t0), ParentOverride(unitId: "g-a", mode: .revisit, at: PSFixtures.t0)]
        s.sessions = PSFixtures.snapshot(sessions: 1).sessions
        s.sessions[0].unitsPractised = ["g-s", "g-gone"]
        let result = try SnapshotSanitizer.sanitize(s, curriculum: cur, now: now)
        XCTAssertEqual(Set(result.snapshot.skills.map { $0.unitId }), ["g-s", "g-a"])
        XCTAssertEqual(result.snapshot.profile.overrides.map { $0.unitId }, ["g-a"])
        XCTAssertEqual(result.snapshot.attempts.count, 3)
        XCTAssertEqual(result.snapshot.sessions[0].unitsPractised, ["g-s"])
        XCTAssertEqual(result.report.droppedSkills, 1)
        XCTAssertEqual(result.report.droppedOverrides, 1)
        XCTAssertEqual(result.report.droppedAttempts, 1)
        XCTAssertFalse(result.report.isClean)
    }

    func testCountsArraysAndSettingsAreClamped() throws {
        var s = PSFixtures.snapshot(id: "p")
        s.profile.nickname = String(repeating: "x", count: 500)
        s.profile.settings.narrationVolume = 7
        s.profile.settings.musicVolume = -3
        s.profile.settings.mastery.minAttempts = -5
        s.profile.settings.mastery.secureScore = 0.0
        s.profile.settings.mastery.reviewLadderDays = []
        s.profile.createdAt = PSFixtures.t0.addingTimeInterval(1000 * 86_400)
        s.profile.baselinePlacementOrder = -4
        s.profile.stickers = (0..<2000).map { "st-\($0)" }
        var k = PSFixtures.skill("g-s")
        k.score = 42
        k.attempts = -9
        k.reviewStage = 99
        k.struggleStreak = -1
        k.sessionsSeen = (0..<1000).map { "s\($0)" }
        k.daysSeen = (0..<1000).map { "d\($0)" }
        k.recentResults = Array(repeating: true, count: 100)
        k.nextReviewAt = PSFixtures.t0.addingTimeInterval(9999 * 86_400)
        s.skills = [k]
        s.confusions = [ConfusionRecord(expected: "a", chosen: "b", count: -3, lastAt: PSFixtures.t0), ConfusionRecord(expected: "a", chosen: "c", count: 10_000_000, lastAt: PSFixtures.t0)]
        s.sessions = PSFixtures.snapshot(sessions: 1).sessions
        s.sessions[0].activitiesDone = 5; s.sessions[0].correct = 500

        let r = try SnapshotSanitizer.sanitize(s, curriculum: nil, now: now).snapshot
        XCTAssertEqual(r.profile.nickname.count, SnapshotSanitizer.maxNicknameLength)
        XCTAssertEqual(r.profile.settings.narrationVolume, 1.0)
        XCTAssertEqual(r.profile.settings.musicVolume, 0.0)
        XCTAssertGreaterThanOrEqual(r.profile.settings.mastery.minAttempts, 1)
        XCTAssertGreaterThanOrEqual(r.profile.settings.mastery.secureScore, 0.5)
        XCTAssertFalse(r.profile.settings.mastery.reviewLadderDays.isEmpty)
        XCTAssertLessThanOrEqual(r.profile.createdAt, now.addingTimeInterval(86_400))
        XCTAssertNil(r.profile.baselinePlacementOrder)
        XCTAssertLessThanOrEqual(r.profile.stickers.count, SnapshotSanitizer.maxStickers)
        let ks = r.skills[0]
        XCTAssertEqual(ks.score, 1.0)
        XCTAssertEqual(ks.attempts, 0)
        XCTAssertEqual(ks.reviewStage, r.profile.settings.mastery.reviewLadderDays.count - 1)
        XCTAssertEqual(ks.struggleStreak, 0)
        XCTAssertLessThanOrEqual(ks.sessionsSeen.count, SnapshotCompactor.defaultMaxSessionsSeenPerSkill)
        XCTAssertLessThanOrEqual(ks.daysSeen.count, SnapshotCompactor.defaultMaxDaysSeenPerSkill)
        XCTAssertLessThanOrEqual(ks.recentResults.count, Mastery.windowSize)
        XCTAssertLessThanOrEqual(ks.nextReviewAt ?? .distantPast, now.addingTimeInterval(400 * 86_400))
        XCTAssertEqual(r.confusions.count, 1)
        XCTAssertEqual(r.confusions[0].count, 100_000)
        XCTAssertEqual(r.sessions[0].correct, 5)
    }

    func testSanitisedSnapshotFitsTheStoreBudget() throws {
        var s = PSFixtures.snapshot(id: "p", attempts: 5000, sessions: 500, confusions: 500)
        s.skills = (0..<80).map { i in
            var k = PSFixtures.skill("u\(i)")
            k.sessionsSeen = (0..<400).map { "plan-\($0)-\(i)" }
            return k
        }
        let r = try SnapshotSanitizer.sanitize(s, curriculum: nil, now: now).snapshot
        XCTAssertLessThanOrEqual(SnapshotCompactor.encodedSize(of: r), SnapshotCompactor.defaultBudget)
        let store = KeyValueLearnerStore(keyValue: InMemoryKeyValueStore())
        XCTAssertNoThrow(try store.save(r))
    }

    func testNewerSchemaSnapshotIsRejectedAndNothingIsWritten() throws {
        var future = PSFixtures.snapshot(id: "future")
        future.profile.schemaVersion = CurriculumSchema.version + 1
        let store = InMemoryLearnerStore()
        XCTAssertThrowsError(try BackupRestoration.restore(payload([PSFixtures.snapshot(id: "fine"), future]), to: store, curriculum: nil, now: now)) { err in
            XCTAssertEqual(err as? StorageError, .newerSchema(found: CurriculumSchema.version + 1, supported: CurriculumSchema.version))
        }
        XCTAssertEqual(try store.listProfileIds(), [], "validation happens before any write")
    }

    func testNewerPayloadFormatIsRejected() {
        let p = BackupPayload(createdAt: PSFixtures.t0, snapshots: [PSFixtures.snapshot()], formatVersion: BackupPayload.currentFormatVersion + 1)
        XCTAssertThrowsError(try BackupRestoration.restore(p, to: InMemoryLearnerStore(), curriculum: nil)) {
            XCTAssertEqual($0 as? StorageError, .unsupportedBackupFormat)
        }
    }

    // MARK: Partial failure

    func testFailureHalfwayRestoresPreviousDataAndActivePointer() throws {
        let store = FailingSaveStore()
        try store.inner.save(PSFixtures.snapshot(id: "a", attempts: 1))
        try store.inner.setActiveProfileId("a")
        store.failOnId = "c"
        let p = payload([PSFixtures.snapshot(id: "a", attempts: 50), PSFixtures.snapshot(id: "b", attempts: 2), PSFixtures.snapshot(id: "c", attempts: 3)])
        XCTAssertThrowsError(try BackupRestoration.restore(p, to: store, curriculum: nil, overwrite: true, now: now)) {
            XCTAssertEqual($0 as? StorageError, .writeFailed(key: "boom"))
        }
        XCTAssertEqual(try store.listProfileIds(), ["a"], "the new profile written before the failure is removed again")
        XCTAssertEqual(try store.load(profileId: "a")?.attempts.count, 1, "the overwritten profile is put back")
        XCTAssertEqual(try store.activeProfileId(), "a")
    }

    func testRealStoreEndToEndRestoreOverAFreshProfile() throws {
        let kv = InMemoryKeyValueStore()
        let store = KeyValueLearnerStore(keyValue: kv)
        try store.save(PSFixtures.snapshot(id: "fresh"))
        let cur = try PSFixtures.curriculum(unitIds: ["g-s"])
        let out = try BackupRestoration.restore(payload([PSFixtures.snapshot(id: "child", attempts: 12)]), to: store, curriculum: cur, now: now)
        XCTAssertEqual(out.activeProfileId, "child")
        // The app's next launch opens the restored profile, even though "fresh" sorts first and was saved earlier.
        XCTAssertEqual(try store.loadActiveOrMostRecentValid().snapshot?.profile.id, "child")
        XCTAssertEqual(try KeyValueLearnerStore(keyValue: kv).activeProfileId(), "child")
    }
}
