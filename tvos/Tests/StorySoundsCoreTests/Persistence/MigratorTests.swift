import XCTest
@testable import StorySoundsCore

final class MigratorTests: XCTestCase {
    private func envelopeJSON(version: Int, nickname: String = "Robin") throws -> Data {
        var env = SnapshotEnvelope(savedAt: PSFixtures.t0, snapshot: PSFixtures.snapshot())
        env.snapshot.profile.nickname = nickname
        env.schemaVersion = version
        return try SnapshotCodec.encode(env)
    }

    func testCurrentVersionDecodesWithoutMigration() throws {
        let r = try Migrator.standard.decodeEnvelope(from: try envelopeJSON(version: 1))
        XCTAssertNil(r.migratedFrom)
        XCTAssertEqual(r.envelope.snapshot.profile.nickname, "Robin")
        XCTAssertEqual(r.envelope.savedAt, PSFixtures.t0)
    }

    func testNewerSchemaIsRejected() throws {
        XCTAssertThrowsError(try Migrator.standard.decodeEnvelope(from: try envelopeJSON(version: 99))) { err in
            XCTAssertEqual(err as? StorageError, .newerSchema(found: 99, supported: 1))
        }
    }

    func testOrderedMigrationsRunInSequence() throws {
        var order: [Int] = []
        let m = Migrator(currentVersion: 3, migrations: [
            Migration(from: 2, to: 3) { obj in
                order.append(2)
                var o = obj; var snap = o["snapshot"] as! [String: Any]; var p = snap["profile"] as! [String: Any]
                p["nickname"] = (p["nickname"] as! String) + "-v3"; snap["profile"] = p; o["snapshot"] = snap; return o
            },
            Migration(from: 1, to: 2) { obj in
                order.append(1)
                var o = obj; var snap = o["snapshot"] as! [String: Any]; var p = snap["profile"] as! [String: Any]
                p["nickname"] = (p["nickname"] as! String) + "-v2"; snap["profile"] = p; o["snapshot"] = snap; return o
            },
        ])
        let r = try m.decodeEnvelope(from: try envelopeJSON(version: 1))
        XCTAssertEqual(order, [1, 2])
        XCTAssertEqual(r.migratedFrom, 1)
        XCTAssertEqual(r.envelope.schemaVersion, 3)
        XCTAssertEqual(r.envelope.snapshot.profile.nickname, "Robin-v2-v3")
    }

    func testMissingMigrationIsCorrupt() throws {
        let m = Migrator(currentVersion: 3, migrations: [Migration(from: 2, to: 3) { $0 }])
        XCTAssertThrowsError(try m.decodeEnvelope(from: try envelopeJSON(version: 1))) { err in
            guard case StorageError.corrupt = err else { return XCTFail("wrong error \(err)") }
        }
    }

    func testGarbageIsCorrupt() {
        XCTAssertThrowsError(try Migrator.standard.decodeEnvelope(from: Data("xx".utf8)))
        XCTAssertThrowsError(try Migrator.standard.decodeEnvelope(from: Data("{}".utf8)))
    }

    func testReconcileDropsVanishedUnitsButKeepsHistory() throws {
        var s = PSFixtures.snapshot(attempts: 4, sessions: 2, confusions: 1,
                                    skills: [PSFixtures.skill("keep"), PSFixtures.skill("gone"), PSFixtures.skill("gone", .blend)])
        s.profile.overrides = [ParentOverride(unitId: "keep", mode: .unlocked, at: PSFixtures.t0),
                               ParentOverride(unitId: "gone", mode: .revisit, at: PSFixtures.t0)]
        s.profile.stickers = ["star"]
        let c = try PSFixtures.curriculum(unitIds: ["keep", "new"])
        let (out, report) = Migrator.reconcile(s, with: c)
        XCTAssertEqual(out.skills.map { $0.unitId }, ["keep"])
        XCTAssertEqual(out.profile.overrides.map { $0.unitId }, ["keep"])
        XCTAssertEqual(out.attempts.count, 4)
        XCTAssertEqual(out.sessions.count, 2)
        XCTAssertEqual(out.confusions.count, 1)
        XCTAssertEqual(out.profile.stickers, ["star"])
        XCTAssertEqual(out.profile.contentVersion, "9.9.9")
        XCTAssertEqual(report, ReconcileReport(removedSkills: 2, removedOverrides: 1, droppedUnitIds: ["gone"], contentVersionChanged: true))
    }

    func testStoreUsesMigratorOnLoad() throws {
        let kv = InMemoryKeyValueStore()
        let v2 = Migrator(currentVersion: 2, migrations: [Migration(from: 1, to: 2) { $0 }])
        let writer = KeyValueLearnerStore(keyValue: kv)
        try writer.save(PSFixtures.snapshot(attempts: 2))
        let reader = KeyValueLearnerStore(keyValue: kv, migrator: v2)
        XCTAssertEqual(try reader.load(profileId: "p1")?.attempts.count, 2)
    }
}
