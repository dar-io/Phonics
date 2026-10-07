import XCTest
@testable import StorySoundsCore

final class LearnerStoreTests: XCTestCase {
    private func makeDefaults() -> (UserDefaults, String) {
        let name = "storysounds.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        return (d, name)
    }

    func testUserDefaultsRoundTripAndList() throws {
        let (d, name) = makeDefaults(); defer { d.removePersistentDomain(forName: name) }
        let store = UserDefaultsLearnerStore(defaults: d)
        XCTAssertNil(try store.load(profileId: "a"))
        try store.save(PSFixtures.snapshot(id: "a", attempts: 3))
        try store.save(PSFixtures.snapshot(id: "b.weird id", attempts: 1))
        XCTAssertEqual(try store.listProfileIds(), ["a", "b.weird id"])
        let loaded = try XCTUnwrap(try store.load(profileId: "a"))
        XCTAssertEqual(loaded.attempts.count, 3)
        XCTAssertEqual(loaded.profile.nickname, "Robin")
        XCTAssertEqual(loaded.attempts.first?.at, PSFixtures.t0)
    }

    func testSaveReplacesAndLeavesNoOrphanGenerations() throws {
        let kv = InMemoryKeyValueStore()
        let store = KeyValueLearnerStore(keyValue: kv)
        for i in 1...4 { try store.save(PSFixtures.snapshot(attempts: i)) }
        XCTAssertEqual(try store.load(profileId: "p1")?.attempts.count, 4)
        let snapKeys = kv.allKeys().filter { $0.contains(".snap.") }
        XCTAssertEqual(snapKeys.count, 1)
    }

    func testUserScopeIsolatesData() throws {
        let kv = InMemoryKeyValueStore()
        let a = KeyValueLearnerStore(keyValue: kv, userScope: "household-1")
        let b = KeyValueLearnerStore(keyValue: kv, userScope: "household-2")
        try a.save(PSFixtures.snapshot(id: "p1", attempts: 1))
        XCTAssertEqual(try b.listProfileIds(), [])
        XCTAssertNil(try b.load(profileId: "p1"))
        try a.deleteAll()
        XCTAssertTrue(kv.allKeys().isEmpty)
    }

    func testFailedSaveDoesNotCorruptPreviousValue_quota() throws {
        let first = PSFixtures.snapshot(attempts: 5)
        let size = SnapshotCompactor.encodedSize(of: first)
        // Room for one copy only: the second generation cannot be written.
        let kv = InMemoryKeyValueStore(quotaBytes: size + 200)
        let store = KeyValueLearnerStore(keyValue: kv)
        try store.save(first)
        XCTAssertThrowsError(try store.save(PSFixtures.snapshot(attempts: 6)))
        XCTAssertEqual(try store.load(profileId: "p1")?.attempts.count, 5)
    }

    func testFailedPointerWriteKeepsOldValueAndCleansUp() throws {
        let kv = InMemoryKeyValueStore()
        let store = KeyValueLearnerStore(keyValue: kv)
        try store.save(PSFixtures.snapshot(attempts: 2))
        kv.failWrites = { $0.contains(".ptr.") }
        XCTAssertThrowsError(try store.save(PSFixtures.snapshot(attempts: 9)))
        kv.failWrites = nil
        XCTAssertEqual(try store.load(profileId: "p1")?.attempts.count, 2)
        XCTAssertEqual(kv.allKeys().filter { $0.contains(".snap.") }.count, 1)
    }

    func testSilentlyDroppedWriteIsDetected() throws {
        let kv = InMemoryKeyValueStore()
        let store = KeyValueLearnerStore(keyValue: kv)
        try store.save(PSFixtures.snapshot(attempts: 2))
        kv.silentlyDropWrites = { $0.contains(".snap.") }
        XCTAssertThrowsError(try store.save(PSFixtures.snapshot(attempts: 3))) { err in
            guard case StorageError.verificationFailed = err else { return XCTFail("wrong error \(err)") }
        }
        kv.silentlyDropWrites = nil
        XCTAssertEqual(try store.load(profileId: "p1")?.attempts.count, 2)
    }

    func testTooLargeIsRejectedWithoutTouchingStore() throws {
        let kv = InMemoryKeyValueStore()
        let store = KeyValueLearnerStore(keyValue: kv, maxBytes: 1_000)
        XCTAssertThrowsError(try store.save(PSFixtures.snapshot(attempts: 50))) { err in
            guard case StorageError.tooLarge = err else { return XCTFail("wrong error \(err)") }
        }
        XCTAssertTrue(kv.allKeys().isEmpty)
    }

    func testDeleteProfileRemovesAllItsKeys() throws {
        let kv = InMemoryKeyValueStore()
        let store = KeyValueLearnerStore(keyValue: kv)
        try store.save(PSFixtures.snapshot(id: "a")); try store.save(PSFixtures.snapshot(id: "b"))
        try store.delete(profileId: "a")
        XCTAssertEqual(try store.listProfileIds(), ["b"])
        XCTAssertTrue(kv.allKeys().allSatisfy { !$0.contains(".snap.a.") && !$0.contains(".ptr.a") })
    }

    func testCorruptDataThrowsCorrupt() throws {
        let kv = InMemoryKeyValueStore()
        let store = KeyValueLearnerStore(keyValue: kv)
        try store.save(PSFixtures.snapshot())
        let snapKey = try XCTUnwrap(kv.allKeys().first { $0.contains(".snap.") })
        try kv.setData(Data("not json".utf8), forKey: snapKey)
        XCTAssertThrowsError(try store.load(profileId: "p1")) { err in
            guard case StorageError.corrupt = err else { return XCTFail("wrong error \(err)") }
        }
    }

    func testInMemoryStoreBasics() throws {
        let store = InMemoryLearnerStore()
        try store.save(PSFixtures.snapshot(id: "x", attempts: 2))
        XCTAssertEqual(try store.listProfileIds(), ["x"])
        store.saveError = StorageError.writeFailed(key: "k")
        XCTAssertThrowsError(try store.save(PSFixtures.snapshot(id: "x", attempts: 5)))
        XCTAssertEqual(try store.load(profileId: "x")?.attempts.count, 2)
        store.saveError = nil
        try store.deleteAll()
        XCTAssertEqual(try store.listProfileIds(), [])
    }
}
