import XCTest
@testable import StorySoundsCore

/// Storage budget, stale-generation reclaim, active-profile pointer and "most recent valid profile" selection.
final class StorageHardeningTests: XCTestCase {
    private func snapKeys(_ kv: InMemoryKeyValueStore) -> [String] {
        return kv.allKeys().filter { $0.contains(".snap.") }.sorted()
    }

    // MARK: Budget

    func testDefaultsKeepTwoGenerationsWellUnderTheTvOSLimit() {
        XCTAssertLessThanOrEqual(SnapshotCompactor.defaultBudget, 150_000)
        XCTAssertLessThanOrEqual(KeyValueLearnerStore.defaultMaxBytes, 200_000)
        // Old + new generation of one profile at the cap.
        XCTAssertLessThanOrEqual(2 * KeyValueLearnerStore.defaultMaxBytes, 400_000)
        XCTAssertLessThanOrEqual(2 * SnapshotCompactor.defaultBudget, 300_000)
    }

    func testRepeatedSavesNeverHoldMoreThanTwoGenerationsAtOnce() throws {
        let one = PSFixtures.snapshot(attempts: 40)
        let size = SnapshotCompactor.encodedSize(of: one)
        // Quota allows two copies but not three: any leak of a third generation would throw.
        let kv = InMemoryKeyValueStore(quotaBytes: size * 2 + 400)
        let store = KeyValueLearnerStore(keyValue: kv)
        for _ in 0..<8 { try store.save(one) }
        XCTAssertEqual(snapKeys(kv).count, 1)
        XCTAssertLessThan(kv.totalBytes, size + 400)
    }

    func testSessionsSeenAndDaysSeenAreCappedByTheCompactor() {
        var k = PSFixtures.skill("g-s")
        k.sessionsSeen = (0..<500).map { "plan-\($0)" }
        k.daysSeen = (0..<500).map { "2024-01-\($0)" }
        var s = PSFixtures.snapshot()
        s.skills = [k]
        let r = SnapshotCompactor().compact(s)
        XCTAssertLessThanOrEqual(r.snapshot.skills[0].sessionsSeen.count, SnapshotCompactor.defaultMaxSessionsSeenPerSkill)
        XCTAssertLessThanOrEqual(r.snapshot.skills[0].daysSeen.count, SnapshotCompactor.defaultMaxDaysSeenPerSkill)
        XCTAssertEqual(r.snapshot.skills[0].sessionsSeen.last, "plan-499", "the newest entries are kept")
    }

    func testMasteryNeverGrowsSessionOrDayHistoryPastTheCap() {
        var skill = SkillState(unitId: "g-s", track: .recognise)
        for i in 0..<120 {
            let at = PSFixtures.t0.addingTimeInterval(Double(i) * 86_400)
            let a = Attempt(at: at, sessionId: "s\(i)", unitId: "g-s", track: .recognise, activityType: .listenChooseSound,
                            itemKey: "k", correct: true, support: .independent)
            skill = Mastery.update(skill: skill, attempt: a, settings: MasterySettings(), now: at)
        }
        XCTAssertLessThanOrEqual(skill.sessionsSeen.count, SnapshotCompactor.defaultMaxSessionsSeenPerSkill)
        XCTAssertLessThanOrEqual(skill.daysSeen.count, SnapshotCompactor.defaultMaxDaysSeenPerSkill)
    }

    func testPlanSessionIdsAreShort() {
        let id = SessionPlanner.sessionId(seed: UInt64.max, now: Date(timeIntervalSince1970: 1_900_000_000))
        XCTAssertLessThanOrEqual(id.count, 20, id)
        XCTAssertTrue(id.hasPrefix("plan-"))
    }

    // MARK: Stale generations

    func testOrphanGenerationLeftByACrashIsSweptOnNextSave() throws {
        let kv = InMemoryKeyValueStore()
        let store = KeyValueLearnerStore(keyValue: kv)
        try store.save(PSFixtures.snapshot(attempts: 2))
        // Simulate: pointer flipped, process died before the old generation was deleted -> an extra generation key.
        let live = try XCTUnwrap(snapKeys(kv).first)
        let base = String(live.dropLast(1))
        try kv.setData(Data("old".utf8), forKey: base + "0")
        try kv.setData(Data("newer orphan".utf8), forKey: base + "77")
        XCTAssertEqual(snapKeys(kv).count, 3)
        try store.save(PSFixtures.snapshot(attempts: 3))
        XCTAssertEqual(snapKeys(kv).count, 1)
        XCTAssertEqual(try store.load(profileId: "p1")?.attempts.count, 3)
    }

    func testOrphanGenerationIsSweptOnLoad() throws {
        let kv = InMemoryKeyValueStore()
        let store = KeyValueLearnerStore(keyValue: kv)
        try store.save(PSFixtures.snapshot(attempts: 2))
        let live = try XCTUnwrap(snapKeys(kv).first)
        try kv.setData(Data("orphan".utf8), forKey: String(live.dropLast(1)) + "9")
        XCTAssertEqual(snapKeys(kv).count, 2)
        XCTAssertEqual(try store.load(profileId: "p1")?.attempts.count, 2)
        XCTAssertEqual(snapKeys(kv), [live])
    }

    func testSnapshotKeysWithoutAPointerAreReclaimed() throws {
        let kv = InMemoryKeyValueStore()
        let store = KeyValueLearnerStore(keyValue: kv)
        try store.save(PSFixtures.snapshot(id: "a"))
        try store.save(PSFixtures.snapshot(id: "b"))
        // A crash during delete(): the pointer is gone, the data is not.
        let ptr = try XCTUnwrap(kv.allKeys().first { $0.contains(".ptr.a") })
        try kv.setData(nil, forKey: ptr)
        XCTAssertEqual(try store.listProfileIds(), ["b"])
        XCTAssertTrue(snapKeys(kv).allSatisfy { !$0.contains(".snap.a.") })
        XCTAssertEqual(snapKeys(kv).count, 1)
    }

    // MARK: Active profile pointer

    func testActiveProfilePointerRoundTripsAndSurvivesANewStoreInstance() throws {
        let kv = InMemoryKeyValueStore()
        let store = KeyValueLearnerStore(keyValue: kv)
        XCTAssertNil(try store.activeProfileId())
        try store.save(PSFixtures.snapshot(id: "a")); try store.save(PSFixtures.snapshot(id: "b"))
        try store.setActiveProfileId("b")
        XCTAssertEqual(try store.activeProfileId(), "b")
        XCTAssertEqual(try KeyValueLearnerStore(keyValue: kv).activeProfileId(), "b")
        XCTAssertEqual(try store.listProfileIds(), ["a", "b"], "the pointer key is not a profile")
        XCTAssertThrowsError(try store.setActiveProfileId("missing")) { XCTAssertEqual($0 as? StorageError, .notFound) }
        try store.setActiveProfileId(nil)
        XCTAssertNil(try store.activeProfileId())
    }

    func testDeletingTheActiveProfileClearsThePointer() throws {
        let store = KeyValueLearnerStore(keyValue: InMemoryKeyValueStore())
        try store.save(PSFixtures.snapshot(id: "a"))
        try store.setActiveProfileId("a")
        try store.delete(profileId: "a")
        XCTAssertNil(try store.activeProfileId())
    }

    func testInMemoryStoreSupportsTheActivePointerToo() throws {
        let store = InMemoryLearnerStore()
        try store.save(PSFixtures.snapshot(id: "a"))
        try store.setActiveProfileId("a")
        XCTAssertEqual(try store.activeProfileId(), "a")
        try store.deleteAll()
        XCTAssertNil(try store.activeProfileId())
    }

    // MARK: Most recent valid profile

    private final class Ticker: @unchecked Sendable {
        var now = PSFixtures.t0
    }

    private func corrupt(_ kv: InMemoryKeyValueStore, profile: String) throws {
        let key = try XCTUnwrap(kv.allKeys().first { $0.contains(".snap." + profile + ".") })
        try kv.setData(Data("not json".utf8), forKey: key)
    }

    func testMostRecentValidSkipsACorruptProfileAndReportsIt() throws {
        let kv = InMemoryKeyValueStore()
        let t = Ticker()
        let store = KeyValueLearnerStore(keyValue: kv, clock: { t.now })
        t.now = PSFixtures.t0;                          try store.save(PSFixtures.snapshot(id: "old", attempts: 1))
        t.now = PSFixtures.t0.addingTimeInterval(100);  try store.save(PSFixtures.snapshot(id: "good", attempts: 2))
        t.now = PSFixtures.t0.addingTimeInterval(200);  try store.save(PSFixtures.snapshot(id: "newest", attempts: 3))
        try corrupt(kv, profile: "newest")

        let outcome = try store.loadMostRecentValid()
        XCTAssertEqual(outcome.snapshot?.profile.id, "good", "newest by savedAt among profiles that decode")
        XCTAssertEqual(outcome.profileIds, ["good", "newest", "old"])
        XCTAssertEqual(outcome.failures.map { $0.profileId }, ["newest"])
        guard case .corrupt = outcome.failures[0].reason else { return XCTFail("expected corrupt") }
        XCTAssertTrue(outcome.hadFailures)
        XCTAssertFalse(outcome.onlyUnreadableData)
        // Nothing was discarded: the unreadable profile is still listed and its pointer still exists.
        XCTAssertTrue(try store.listProfileIds().contains("newest"))
    }

    func testMostRecentValidPicksNewestSavedAtNotLowestId() throws {
        let kv = InMemoryKeyValueStore()
        let t = Ticker()
        let store = KeyValueLearnerStore(keyValue: kv, clock: { t.now })
        t.now = PSFixtures.t0.addingTimeInterval(500); try store.save(PSFixtures.snapshot(id: "zzz"))
        t.now = PSFixtures.t0.addingTimeInterval(900); try store.save(PSFixtures.snapshot(id: "mmm"))
        t.now = PSFixtures.t0.addingTimeInterval(100); try store.save(PSFixtures.snapshot(id: "aaa"))
        XCTAssertEqual(try store.loadMostRecentValid().snapshot?.profile.id, "mmm")
        XCTAssertEqual(try store.loadMostRecentValid().stored?.savedAt, PSFixtures.t0.addingTimeInterval(900))
    }

    func testOnlyUnreadableDataIsFlaggedSoTheAppDoesNotQuietlyStartOver() throws {
        let kv = InMemoryKeyValueStore()
        let store = KeyValueLearnerStore(keyValue: kv)
        try store.save(PSFixtures.snapshot(id: "a"))
        try corrupt(kv, profile: "a")
        let before = kv.allKeys().sorted()
        let outcome = try store.loadMostRecentValid()
        XCTAssertNil(outcome.snapshot)
        XCTAssertTrue(outcome.onlyUnreadableData)
        XCTAssertEqual(outcome.failures.count, 1)
        XCTAssertEqual(kv.allKeys().sorted(), before, "loading must not modify or delete unreadable data")
    }

    func testNewerSchemaProfileIsReportedAsSuch() throws {
        let kv = InMemoryKeyValueStore()
        let store = KeyValueLearnerStore(keyValue: kv)
        try store.save(PSFixtures.snapshot(id: "future"))
        try store.save(PSFixtures.snapshot(id: "now"))
        let key = try XCTUnwrap(kv.allKeys().first { $0.contains(".snap.future.") })
        try kv.setData(Data("{\"schemaVersion\":99,\"savedAt\":0,\"snapshot\":{}}".utf8), forKey: key)
        let outcome = try store.loadMostRecentValid()
        XCTAssertEqual(outcome.snapshot?.profile.id, "now")
        XCTAssertEqual(outcome.failures, [ProfileLoadFailure(profileId: "future", reason: .newerSchema(found: 99, supported: SnapshotEnvelope.currentSchemaVersion))])
    }

    func testNoProfilesAtAllIsNotAFailure() throws {
        let outcome = try KeyValueLearnerStore(keyValue: InMemoryKeyValueStore()).loadMostRecentValid()
        XCTAssertNil(outcome.snapshot)
        XCTAssertFalse(outcome.hadFailures)
        XCTAssertFalse(outcome.onlyUnreadableData)
        XCTAssertTrue(outcome.profileIds.isEmpty)
    }

    func testActivePointerWinsOverNewerProfileAndFallsBackWhenUnusable() throws {
        let kv = InMemoryKeyValueStore()
        let t = Ticker()
        let store = KeyValueLearnerStore(keyValue: kv, clock: { t.now })
        t.now = PSFixtures.t0;                         try store.save(PSFixtures.snapshot(id: "child"))
        t.now = PSFixtures.t0.addingTimeInterval(50);  try store.save(PSFixtures.snapshot(id: "other"))
        try store.setActiveProfileId("child")
        let chosen = try store.loadActiveOrMostRecentValid()
        XCTAssertEqual(chosen.snapshot?.profile.id, "child")
        XCTAssertFalse(chosen.activePointerWasUnusable)

        try corrupt(kv, profile: "child")
        let fallback = try store.loadActiveOrMostRecentValid()
        XCTAssertEqual(fallback.snapshot?.profile.id, "other")
        XCTAssertTrue(fallback.activePointerWasUnusable)
        XCTAssertEqual(fallback.failures.map { $0.profileId }, ["child"])
    }

    func testInMemoryStoreUsesTheSameSelectionRules() throws {
        let t = Ticker()
        let store = InMemoryLearnerStore(clock: { t.now })
        t.now = PSFixtures.t0;                         try store.save(PSFixtures.snapshot(id: "a"))
        t.now = PSFixtures.t0.addingTimeInterval(10);  try store.save(PSFixtures.snapshot(id: "b"))
        XCTAssertEqual(try store.loadMostRecentValid().snapshot?.profile.id, "b")
    }
}
