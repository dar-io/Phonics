import Foundation

// MARK: Privacy settings (stored separately from learner data; default OFF)

/// Parent-controlled privacy switches. Stored separately from learner snapshots so deleting a learner does not
/// silently re-enable anything, and so the default is always "nothing leaves this device".
public struct PrivacySettings: Codable, Equatable, Sendable {
    /// Explicit parent opt-in to iCloud backup. Default false.
    public var iCloudBackupEnabled: Bool = false
    public var lastBackupAt: Date?
    public init() {}
}

public final class PrivacySettingsStore: @unchecked Sendable {
    private let kv: KeyValueStoring
    private let key: String
    private let lock = NSLock()

    public init(keyValue: KeyValueStoring, userScope: String? = nil) {
        self.kv = keyValue
        self.key = StorageNamespace.root + "privacy." + StorageNamespace.scopeToken(userScope)
    }
    /// Falls back to defaults (backup OFF) if nothing is stored or the bytes are unreadable.
    public func load() -> PrivacySettings {
        lock.lock(); defer { lock.unlock() }
        guard let d = kv.data(forKey: key), let s = try? SnapshotCodec.decode(PrivacySettings.self, from: d) else { return PrivacySettings() }
        return s
    }
    public func save(_ settings: PrivacySettings) throws {
        lock.lock(); defer { lock.unlock() }
        try kv.setData(try SnapshotCodec.encode(settings), forKey: key)
    }
    public func delete() throws { lock.lock(); defer { lock.unlock() }; try kv.setData(nil, forKey: key) }
}

// MARK: Backup payload codec

public struct BackupPayload: Codable, Sendable {
    public static let currentFormatVersion = 1
    public var formatVersion: Int
    public var createdAt: Date
    public var snapshots: [LearnerSnapshot]
    public init(createdAt: Date, snapshots: [LearnerSnapshot], formatVersion: Int = BackupPayload.currentFormatVersion) {
        self.formatVersion = formatVersion; self.createdAt = createdAt; self.snapshots = snapshots
    }
}

/// Binary layout: `"SSB"` magic (3 bytes) | format version (1 byte) | compression (1 byte: 0 none, 1 LZFSE) | body.
public enum BackupCodec {
    /// NSUbiquitousKeyValueStore allows ~1 MB in total; stay clear of it.
    public static let defaultMaxBytes = 700_000
    private static let magic: [UInt8] = [0x53, 0x53, 0x42]
    private static let headerSize = 5

    public static func encode(_ payload: BackupPayload, maxBytes: Int = defaultMaxBytes) throws -> Data {
        let json = try SnapshotCodec.encode(payload)
        var method: UInt8 = 0
        var body = json
        #if canImport(Darwin)
        if let nsData = try? (json as NSData).compressed(using: .lzfse) {
            let c = nsData as Data
            if c.count < json.count { body = c; method = 1 }
        }
        #endif
        var out = Data(magic)
        out.append(UInt8(BackupPayload.currentFormatVersion))
        out.append(method)
        out.append(body)
        guard out.count <= maxBytes else { throw StorageError.tooLarge(bytes: out.count, budget: maxBytes) }
        return out
    }

    public static func decode(_ data: Data) throws -> BackupPayload {
        let bytes = [UInt8](data)
        guard bytes.count > headerSize, Array(bytes.prefix(3)) == magic else { throw StorageError.corrupt("bad backup header") }
        let version = Int(bytes[3])
        guard version <= BackupPayload.currentFormatVersion else { throw StorageError.unsupportedBackupFormat }
        let method = bytes[4]
        let body = Data(bytes.suffix(from: headerSize))
        let json: Data
        switch method {
        case 0: json = body
        #if canImport(Darwin)
        case 1:
            do {
                let ns = try (body as NSData).decompressed(using: .lzfse)
                json = ns as Data
            } catch { throw StorageError.corrupt("decompress failed") }
        #endif
        default: throw StorageError.unsupportedBackupFormat
        }
        do { return try SnapshotCodec.decode(BackupPayload.self, from: json) }
        catch { throw StorageError.corrupt("backup decode failed: \(error)") }
    }
}

// MARK: Backup service

public struct BackupInfo: Equatable, Sendable {
    public let createdAt: Date
    public let profileCount: Int
    public let byteCount: Int
}

public protocol BackupService: AnyObject {
    /// False when the backing service is unusable (e.g. no iCloud account).
    var isAvailable: Bool { get }
    /// Throws `.notOptedIn` unless the parent has switched backup on.
    func backUp(snapshots: [LearnerSnapshot], now: Date) throws -> BackupInfo
    func latestBackupInfo() -> BackupInfo?
    func restore() throws -> BackupPayload
    /// Always allowed, even when opted out (deletion must work regardless of the switch).
    func deleteBackup() throws
}

/// iCloud key-value backup. tvOS has no file sharing, so this plus the on-screen summary are the only "export" routes;
/// a file export would not be technically appropriate on tvOS.
public final class ICloudKeyValueBackup: BackupService, @unchecked Sendable {
    public static let backupKey = StorageNamespace.root + "backup.v1"

    private let kv: KeyValueStoring
    private let privacy: PrivacySettingsStore
    private let compactor: SnapshotCompactor
    private let maxBytes: Int
    private let availability: () -> Bool

    /// - compactor: backups use a tighter default than the local store (they must fit ~1 MB shared by all profiles).
    public init(keyValue: KeyValueStoring, privacy: PrivacySettingsStore,
                compactor: SnapshotCompactor = SnapshotCompactor(byteBudget: 150_000, maxAttempts: 150, maxSessions: 40, maxConfusions: 40),
                maxBytes: Int = BackupCodec.defaultMaxBytes, availability: @escaping () -> Bool = { true }) {
        self.kv = keyValue; self.privacy = privacy; self.compactor = compactor; self.maxBytes = maxBytes; self.availability = availability
    }

    #if canImport(Darwin)
    /// Production wiring: real NSUbiquitousKeyValueStore, available only when an iCloud account is signed in.
    public static func makeDefault(privacy: PrivacySettingsStore) -> ICloudKeyValueBackup {
        ICloudKeyValueBackup(keyValue: ICloudKeyValueStore(), privacy: privacy,
                             availability: { ICloudKeyValueStore.isICloudAccountAvailable })
    }
    #endif

    public var isAvailable: Bool { availability() }

    public func backUp(snapshots: [LearnerSnapshot], now: Date) throws -> BackupInfo {
        var settings = privacy.load()
        guard settings.iCloudBackupEnabled else { throw StorageError.notOptedIn }
        guard availability() else { throw StorageError.unavailable }
        let compacted = snapshots.map { compactor.compact($0).snapshot }
        let data = try BackupCodec.encode(BackupPayload(createdAt: now, snapshots: compacted), maxBytes: maxBytes)
        try kv.setData(data, forKey: ICloudKeyValueBackup.backupKey)
        settings.lastBackupAt = now
        try? privacy.save(settings)
        return BackupInfo(createdAt: now, profileCount: compacted.count, byteCount: data.count)
    }

    public func latestBackupInfo() -> BackupInfo? {
        guard let d = kv.data(forKey: ICloudKeyValueBackup.backupKey), let p = try? BackupCodec.decode(d) else { return nil }
        return BackupInfo(createdAt: p.createdAt, profileCount: p.snapshots.count, byteCount: d.count)
    }

    public func restore() throws -> BackupPayload {
        guard availability() else { throw StorageError.unavailable }
        guard let d = kv.data(forKey: ICloudKeyValueBackup.backupKey) else { throw StorageError.notFound }
        return try BackupCodec.decode(d)
    }

    public func deleteBackup() throws {
        for k in kv.allKeys() where k.hasPrefix(StorageNamespace.root + "backup.") { try kv.setData(nil, forKey: k) }
    }
}

public enum BackupRestoration {
    /// Writes restored snapshots into `store`, reconciling with the curriculum when given.
    /// Existing profiles are kept unless `overwrite` is true. Returns the ids written.
    @discardableResult
    public static func apply(_ payload: BackupPayload, to store: LearnerStore, curriculum: Curriculum?, overwrite: Bool = false) throws -> [String] {
        var written: [String] = []
        let existing = Set(try store.listProfileIds())
        for snap in payload.snapshots {
            if existing.contains(snap.profile.id) && !overwrite { continue }
            let toSave = curriculum.map { Migrator.reconcile(snap, with: $0).snapshot } ?? snap
            try store.save(toSave)
            written.append(snap.profile.id)
        }
        return written
    }
}

// MARK: Complete deletion

/// "Delete all data": removes every learner snapshot, privacy settings and any iCloud backup.
/// Attempts every step even if one fails, then rethrows the first error so the parent is told the truth.
public final class DataDeletionService {
    private let store: LearnerStore
    private let localKeyValue: KeyValueStoring?
    private let privacy: PrivacySettingsStore?
    private let backup: BackupService?

    public init(store: LearnerStore, localKeyValue: KeyValueStoring? = nil, privacy: PrivacySettingsStore? = nil, backup: BackupService? = nil) {
        self.store = store; self.localKeyValue = localKeyValue; self.privacy = privacy; self.backup = backup
    }

    public func deleteEverything() throws {
        var first: Error?
        func attempt(_ body: () throws -> Void) { do { try body() } catch { if first == nil { first = error } } }
        attempt { try store.deleteAll() }
        attempt {
            if let kv = localKeyValue {
                for k in kv.allKeys() where k.hasPrefix(StorageNamespace.root) { try kv.setData(nil, forKey: k) }
            }
        }
        attempt { if let p = privacy { try p.delete() } }
        attempt { try backup?.deleteBackup() }
        if let e = first { throw e }
    }
}
