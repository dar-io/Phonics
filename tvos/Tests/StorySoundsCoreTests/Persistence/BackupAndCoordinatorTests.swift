import XCTest
@testable import StorySoundsCore

final class BackupTests: XCTestCase {
    private func makeBackup(optIn: Bool, available: Bool = true, kv: InMemoryKeyValueStore = InMemoryKeyValueStore(),
                            local: InMemoryKeyValueStore = InMemoryKeyValueStore(), maxBytes: Int = BackupCodec.defaultMaxBytes)
        -> (ICloudKeyValueBackup, PrivacySettingsStore) {
        let privacy = PrivacySettingsStore(keyValue: local)
        if optIn { var p = PrivacySettings(); p.iCloudBackupEnabled = true; try! privacy.save(p) }
        return (ICloudKeyValueBackup(keyValue: kv, privacy: privacy, maxBytes: maxBytes, availability: { available }), privacy)
    }

    func testPrivacyDefaultsOff() {
        let p = PrivacySettingsStore(keyValue: InMemoryKeyValueStore())
        XCTAssertFalse(p.load().iCloudBackupEnabled)
        XCTAssertNil(p.load().lastBackupAt)
    }

    func testCodecRoundTrip() throws {
        let payload = BackupPayload(createdAt: PSFixtures.t0, snapshots: [PSFixtures.snapshot(id: "a", attempts: 40), PSFixtures.snapshot(id: "b")])
        let data = try BackupCodec.encode(payload)
        let back = try BackupCodec.decode(data)
        XCTAssertEqual(back.formatVersion, BackupPayload.currentFormatVersion)
        XCTAssertEqual(back.createdAt, PSFixtures.t0)
        XCTAssertEqual(back.snapshots.map { $0.profile.id }, ["a", "b"])
        XCTAssertEqual(back.snapshots[0].attempts.count, 40)
    }

    #if canImport(Darwin)
    func testCodecCompresses() throws {
        let payload = BackupPayload(createdAt: PSFixtures.t0, snapshots: [PSFixtures.snapshot(attempts: 300)])
        let raw = try SnapshotCodec.encode(payload)
        XCTAssertLessThan(try BackupCodec.encode(payload).count, raw.count)
    }
    #endif

    func testCodecEnforcesSizeAndRejectsBadHeader() throws {
        let payload = BackupPayload(createdAt: PSFixtures.t0, snapshots: [PSFixtures.snapshot(attempts: 200)])
        XCTAssertThrowsError(try BackupCodec.encode(payload, maxBytes: 100)) { err in
            guard case StorageError.tooLarge = err else { return XCTFail("wrong error \(err)") }
        }
        XCTAssertThrowsError(try BackupCodec.decode(Data("hello world".utf8)))
        XCTAssertThrowsError(try BackupCodec.decode(Data()))
    }

    func testCodecRejectsNewerFormat() throws {
        var data = try BackupCodec.encode(BackupPayload(createdAt: PSFixtures.t0, snapshots: []))
        data[3] = 200
        XCTAssertThrowsError(try BackupCodec.decode(data)) { err in
            XCTAssertEqual(err as? StorageError, .unsupportedBackupFormat)
        }
    }

    func testBackupRequiresOptIn() {
        let (b, _) = makeBackup(optIn: false)
        XCTAssertThrowsError(try b.backUp(snapshots: [PSFixtures.snapshot()], now: PSFixtures.t0)) { err in
            XCTAssertEqual(err as? StorageError, .notOptedIn)
        }
        XCTAssertNil(b.latestBackupInfo())
    }

    func testBackupUnavailableWithoutICloud() {
        let (b, _) = makeBackup(optIn: true, available: false)
        XCTAssertFalse(b.isAvailable)
        XCTAssertThrowsError(try b.backUp(snapshots: [], now: PSFixtures.t0)) { err in
            XCTAssertEqual(err as? StorageError, .unavailable)
        }
    }

    func testBackupAndRestoreRoundTrip() throws {
        let (b, privacy) = makeBackup(optIn: true)
        let info = try b.backUp(snapshots: [PSFixtures.snapshot(id: "a", attempts: 5), PSFixtures.snapshot(id: "b")], now: PSFixtures.t0)
        XCTAssertEqual(info.profileCount, 2)
        XCTAssertEqual(b.latestBackupInfo(), info)
        XCTAssertEqual(privacy.load().lastBackupAt, PSFixtures.t0)
        let payload = try b.restore()
        XCTAssertEqual(payload.snapshots.count, 2)

        let store = InMemoryLearnerStore()
        try store.save(PSFixtures.snapshot(id: "a", attempts: 1))
        let written = try BackupRestoration.apply(payload, to: store, curriculum: try PSFixtures.curriculum(unitIds: ["g-s"]))
        XCTAssertEqual(written, ["b"], "existing profile kept unless overwrite")
        let written2 = try BackupRestoration.apply(payload, to: store, curriculum: nil, overwrite: true)
        XCTAssertEqual(Set(written2), ["a", "b"])
        XCTAssertEqual(try store.load(profileId: "a")?.attempts.count, 5)
    }

    func testRestoreWithNoBackupIsNotFound() {
        let (b, _) = makeBackup(optIn: true)
        XCTAssertThrowsError(try b.restore()) { XCTAssertEqual($0 as? StorageError, .notFound) }
    }

    func testBackupTooLargeSurfacesError() {
        let (b, _) = makeBackup(optIn: true, maxBytes: 200)
        XCTAssertThrowsError(try b.backUp(snapshots: [PSFixtures.snapshot(attempts: 100)], now: PSFixtures.t0))
    }

    func testDeleteEverythingRemovesAllKeysIncludingBackup() throws {
        let cloud = InMemoryKeyValueStore(), local = InMemoryKeyValueStore()
        let (b, privacy) = makeBackup(optIn: true, kv: cloud, local: local)
        let store = KeyValueLearnerStore(keyValue: local)
        let other = KeyValueLearnerStore(keyValue: local, userScope: "other")
        try store.save(PSFixtures.snapshot(id: "a", attempts: 3)); try other.save(PSFixtures.snapshot(id: "z"))
        _ = try b.backUp(snapshots: [PSFixtures.snapshot(id: "a")], now: PSFixtures.t0)
        XCTAssertFalse(cloud.allKeys().isEmpty)

        let svc = DataDeletionService(store: store, localKeyValue: local, privacy: privacy, backup: b)
        try svc.deleteEverything()
        XCTAssertTrue(local.allKeys().isEmpty, "left over: \(local.allKeys())")
        XCTAssertTrue(cloud.allKeys().isEmpty)
        XCTAssertFalse(privacy.load().iCloudBackupEnabled)
    }

    func testDeleteBackupWorksWhenOptedOut() throws {
        let cloud = InMemoryKeyValueStore()
        let (b, privacy) = makeBackup(optIn: true, kv: cloud)
        _ = try b.backUp(snapshots: [PSFixtures.snapshot()], now: PSFixtures.t0)
        try privacy.save(PrivacySettings())
        try b.deleteBackup()
        XCTAssertTrue(cloud.allKeys().isEmpty)
    }
}

final class PersistenceCoordinatorTests: XCTestCase {
    func testFlushNowSavesImmediately() throws {
        let store = InMemoryLearnerStore()
        let c = PersistenceCoordinator(store: store, debounceInterval: 60)
        c.update(PSFixtures.snapshot(attempts: 3))
        c.flushNow()
        XCTAssertEqual(try store.load(profileId: "p1")?.attempts.count, 3)
        XCTAssertFalse(c.hasPendingChanges)
    }

    func testDebouncedSaveCoalescesUpdates() throws {
        let store = InMemoryLearnerStore()
        let c = PersistenceCoordinator(store: store, debounceInterval: 0.2)
        let saved = expectation(description: "saved")
        c.onSaved = { _ in saved.fulfill() }
        c.update(PSFixtures.snapshot(attempts: 1))
        c.update(PSFixtures.snapshot(attempts: 2))
        c.update(PSFixtures.snapshot(attempts: 3))
        wait(for: [saved], timeout: 3)
        c.flushNow()
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(try store.load(profileId: "p1")?.attempts.count, 3)
    }

    func testFlushWithNothingPendingDoesNothing() {
        let store = InMemoryLearnerStore()
        PersistenceCoordinator(store: store).flushNow()
        XCTAssertEqual(store.saveCount, 0)
    }

    func testCompactsBeforeSaving() throws {
        let store = InMemoryLearnerStore()
        let c = PersistenceCoordinator(store: store, compactor: SnapshotCompactor(maxAttempts: 10), debounceInterval: 60)
        c.update(PSFixtures.snapshot(attempts: 50))
        c.flushNow()
        XCTAssertEqual(try store.load(profileId: "p1")?.attempts.count, 10)
    }

    func testFailedSaveSurfacesErrorAndKeepsPendingForRetry() throws {
        let store = InMemoryLearnerStore()
        store.saveError = StorageError.writeFailed(key: "k")
        let c = PersistenceCoordinator(store: store, debounceInterval: 60)
        var reported: Error?
        c.onError = { reported = $0 }
        c.update(PSFixtures.snapshot(attempts: 2))
        c.flushNow()
        XCTAssertNotNil(reported)
        XCTAssertNotNil(c.lastError)
        XCTAssertTrue(c.hasPendingChanges)
        store.saveError = nil
        c.flushNow()
        XCTAssertNil(c.lastError)
        XCTAssertEqual(try store.load(profileId: "p1")?.attempts.count, 2)
    }

    func testCancelPendingDiscards() {
        let store = InMemoryLearnerStore()
        let c = PersistenceCoordinator(store: store, debounceInterval: 60)
        c.update(PSFixtures.snapshot())
        c.cancelPending()
        c.flushNow()
        XCTAssertEqual(store.saveCount, 0)
    }
}
