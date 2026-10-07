import Foundation

/// Versioned wrapper written to disk: `{schemaVersion, savedAt, snapshot}`.
public struct SnapshotEnvelope: Codable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var savedAt: Date
    public var snapshot: LearnerSnapshot
    public init(schemaVersion: Int = SnapshotEnvelope.currentSchemaVersion, savedAt: Date, snapshot: LearnerSnapshot) {
        self.schemaVersion = schemaVersion; self.savedAt = savedAt; self.snapshot = snapshot
    }
}

/// One ordered migration step operating on the raw JSON object of an envelope (`from` -> `to`, `to > from`).
public struct Migration {
    public let from: Int
    public let to: Int
    public let apply: ([String: Any]) throws -> [String: Any]
    public init(from: Int, to: Int, apply: @escaping ([String: Any]) throws -> [String: Any]) {
        self.from = from; self.to = to; self.apply = apply
    }
}

public struct ReconcileReport: Equatable {
    public var removedSkills: Int
    public var removedOverrides: Int
    public var droppedUnitIds: [String]
    public var contentVersionChanged: Bool
}

public struct Migrator {
    public let currentVersion: Int
    public let migrations: [Migration]

    public static let standard = Migrator(currentVersion: SnapshotEnvelope.currentSchemaVersion, migrations: [])

    public init(currentVersion: Int, migrations: [Migration]) {
        self.currentVersion = currentVersion
        self.migrations = migrations.sorted { $0.from < $1.from }
    }

    /// Decodes envelope bytes, applying ordered migrations when the stored version is older.
    /// Throws `.newerSchema` for data written by a newer build (never guesses), `.corrupt` otherwise.
    public func decodeEnvelope(from data: Data) throws -> (envelope: SnapshotEnvelope, migratedFrom: Int?) {
        let raw: Any
        do { raw = try JSONSerialization.jsonObject(with: data) } catch { throw StorageError.corrupt("not JSON") }
        guard var obj = raw as? [String: Any], let version = obj["schemaVersion"] as? Int else {
            throw StorageError.corrupt("missing schemaVersion")
        }
        if version > currentVersion { throw StorageError.newerSchema(found: version, supported: currentVersion) }
        if version == currentVersion {
            do { return (try SnapshotCodec.decode(SnapshotEnvelope.self, from: data), nil) }
            catch { throw StorageError.corrupt("decode failed: \(error)") }
        }
        var v = version
        while v < currentVersion {
            guard let m = migrations.first(where: { $0.from == v }), m.to > m.from else {
                throw StorageError.corrupt("no migration from schema \(v)")
            }
            obj = try m.apply(obj)
            obj["schemaVersion"] = m.to
            v = m.to
        }
        do {
            let bytes = try JSONSerialization.data(withJSONObject: obj)
            return (try SnapshotCodec.decode(SnapshotEnvelope.self, from: bytes), version)
        } catch let e as StorageError { throw e } catch { throw StorageError.corrupt("decode after migration failed: \(error)") }
    }

    /// Aligns a snapshot with the bundled curriculum: drops skills/overrides for units that no longer exist,
    /// keeps all history (attempts, sessions, confusions, stickers) and stamps the content version.
    public static func reconcile(_ snapshot: LearnerSnapshot, with curriculum: Curriculum) -> (snapshot: LearnerSnapshot, report: ReconcileReport) {
        let ids = Set(curriculum.units.map { $0.id })
        var s = snapshot
        let skillsBefore = s.skills.count
        let overridesBefore = s.profile.overrides.count
        var dropped = Set<String>()
        s.skills.forEach { if !ids.contains($0.unitId) { dropped.insert($0.unitId) } }
        s.profile.overrides.forEach { if !ids.contains($0.unitId) { dropped.insert($0.unitId) } }
        s.skills = s.skills.filter { ids.contains($0.unitId) }
        s.profile.overrides = s.profile.overrides.filter { ids.contains($0.unitId) }
        let changed = s.profile.contentVersion != curriculum.contentVersion
        s.profile.contentVersion = curriculum.contentVersion
        s.profile.schemaVersion = CurriculumSchema.version
        return (s, ReconcileReport(removedSkills: skillsBefore - s.skills.count,
                                   removedOverrides: overridesBefore - s.profile.overrides.count,
                                   droppedUnitIds: dropped.sorted(), contentVersionChanged: changed))
    }
}
