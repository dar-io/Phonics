import Foundation

/// Persistence for learner snapshots, one per profile id.
public protocol LearnerStore: AnyObject, Sendable {
    /// Returns nil when nothing is stored for the profile. Throws on corrupt/newer-schema data.
    func load(profileId: String) throws -> LearnerSnapshot?
    /// Must never damage the previously saved value if it throws.
    func save(_ snapshot: LearnerSnapshot) throws
    func delete(profileId: String) throws
    func listProfileIds() throws -> [String]
    func deleteAll() throws
}

/// Core store over any `KeyValueStoring`.
///
/// Key layout (all under `storysounds.learner.<scope>.`):
/// - `snap.<profile>.<generation>`: envelope bytes (JSON)
/// - `ptr.<profile>`: current generation number
///
/// Save = write a NEW generation key, verify it by reading back, then flip the pointer, then delete the old generation.
/// A failure before the pointer flip leaves the previous generation fully intact and still referenced.
/// tvOS caveat: the old and new generation briefly coexist, so peak usage is about 2x the snapshot size.
public final class KeyValueLearnerStore: LearnerStore, @unchecked Sendable {
    public static let defaultMaxBytes = 400_000

    private let kv: KeyValueStoring
    private let prefix: String
    private let maxBytes: Int
    private let migrator: Migrator
    private let clock: () -> Date
    private let lock = NSLock()

    public init(keyValue: KeyValueStoring, userScope: String? = nil, maxBytes: Int = KeyValueLearnerStore.defaultMaxBytes,
                migrator: Migrator = .standard, clock: @escaping () -> Date = { Date() }) {
        self.kv = keyValue
        self.prefix = StorageNamespace.root + "learner." + StorageNamespace.scopeToken(userScope) + "."
        self.maxBytes = maxBytes
        self.migrator = migrator
        self.clock = clock
    }

    private func pointerKey(_ pid: String) -> String { prefix + "ptr." + StorageNamespace.token(pid) }
    private func snapPrefix(_ pid: String) -> String { prefix + "snap." + StorageNamespace.token(pid) + "." }
    private func snapKey(_ pid: String, _ gen: Int) -> String { snapPrefix(pid) + String(gen) }

    private func generation(_ pid: String) -> Int? {
        guard let d = kv.data(forKey: pointerKey(pid)), let s = String(data: d, encoding: .utf8) else { return nil }
        return Int(s)
    }

    public func load(profileId: String) throws -> LearnerSnapshot? {
        lock.lock(); defer { lock.unlock() }
        guard let gen = generation(profileId) else { return nil }
        guard let data = kv.data(forKey: snapKey(profileId, gen)) else { throw StorageError.corrupt("pointer without data") }
        return try migrator.decodeEnvelope(from: data).envelope.snapshot
    }

    public func save(_ snapshot: LearnerSnapshot) throws {
        lock.lock(); defer { lock.unlock() }
        let pid = snapshot.profile.id
        let envelope = SnapshotEnvelope(savedAt: clock(), snapshot: snapshot)
        let data = try SnapshotCodec.encode(envelope)
        guard data.count <= maxBytes else { throw StorageError.tooLarge(bytes: data.count, budget: maxBytes) }

        let oldGen = generation(pid)
        let newGen = (oldGen ?? 0) + 1
        let newKey = snapKey(pid, newGen)
        do {
            try kv.setData(data, forKey: newKey)
            guard kv.data(forKey: newKey) == data else { throw StorageError.verificationFailed(key: newKey) }
        } catch {
            try? kv.setData(nil, forKey: newKey)
            throw error
        }
        let ptrData = Data(String(newGen).utf8)
        do {
            try kv.setData(ptrData, forKey: pointerKey(pid))
            guard kv.data(forKey: pointerKey(pid)) == ptrData else { throw StorageError.verificationFailed(key: pointerKey(pid)) }
        } catch {
            // Restore the old pointer if we can, drop the new generation; the old value stays valid.
            if let old = oldGen { try? kv.setData(Data(String(old).utf8), forKey: pointerKey(pid)) }
            try? kv.setData(nil, forKey: newKey)
            throw error
        }
        if let old = oldGen { try? kv.setData(nil, forKey: snapKey(pid, old)) }
    }

    public func delete(profileId: String) throws {
        lock.lock(); defer { lock.unlock() }
        try deleteLocked(profileId)
    }

    private func deleteLocked(_ pid: String) throws {
        // Remove the pointer first so the profile disappears even if a data key removal were to fail.
        try kv.setData(nil, forKey: pointerKey(pid))
        let sp = snapPrefix(pid)
        for k in kv.allKeys() where k.hasPrefix(sp) { try kv.setData(nil, forKey: k) }
    }

    public func listProfileIds() throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        let p = prefix + "ptr."
        return kv.allKeys().filter { $0.hasPrefix(p) }
            .map { StorageNamespace.untoken(String($0.dropFirst(p.count))) }.sorted()
    }

    /// Removes every key of this store's scope (including orphaned generations).
    public func deleteAll() throws {
        lock.lock(); defer { lock.unlock() }
        for k in kv.allKeys() where k.hasPrefix(prefix) { try kv.setData(nil, forKey: k) }
    }

    /// Removes every key the app ever wrote under `StorageNamespace.root`, for all scopes.
    public func deleteEverythingInAllScopes() throws {
        lock.lock(); defer { lock.unlock() }
        for k in kv.allKeys() where k.hasPrefix(StorageNamespace.root) { try kv.setData(nil, forKey: k) }
    }
}

/// UserDefaults-backed store. Inject a suite (`UserDefaults(suiteName:)`) in tests.
/// `userScope` namespaces data per tvOS household user (pass the TVUserManager identifier as a plain String;
/// Core does not import TVServices).
public final class UserDefaultsLearnerStore: LearnerStore, @unchecked Sendable {
    private let inner: KeyValueLearnerStore
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard, userScope: String? = nil,
                maxBytes: Int = KeyValueLearnerStore.defaultMaxBytes) {
        self.defaults = defaults
        self.inner = KeyValueLearnerStore(keyValue: UserDefaultsKeyValueStore(defaults: defaults), userScope: userScope, maxBytes: maxBytes)
    }
    public func load(profileId: String) throws -> LearnerSnapshot? { try inner.load(profileId: profileId) }
    public func save(_ snapshot: LearnerSnapshot) throws { try inner.save(snapshot) }
    public func delete(profileId: String) throws { try inner.delete(profileId: profileId) }
    public func listProfileIds() throws -> [String] { try inner.listProfileIds() }
    public func deleteAll() throws { try inner.deleteAll() }
    public func deleteEverythingInAllScopes() throws { try inner.deleteEverythingInAllScopes() }
}

/// Test double. Can be told to fail the next saves.
public final class InMemoryLearnerStore: LearnerStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: LearnerSnapshot] = [:]
    /// If set, `save` throws this error (and leaves previous data untouched).
    public var saveError: Error?
    public private(set) var saveCount = 0

    public init() {}

    public func load(profileId: String) throws -> LearnerSnapshot? { lock.lock(); defer { lock.unlock() }; return items[profileId] }
    public func save(_ snapshot: LearnerSnapshot) throws {
        lock.lock(); defer { lock.unlock() }
        if let e = saveError { throw e }
        saveCount += 1
        items[snapshot.profile.id] = snapshot
    }
    public func delete(profileId: String) throws { lock.lock(); defer { lock.unlock() }; items[profileId] = nil }
    public func listProfileIds() throws -> [String] { lock.lock(); defer { lock.unlock() }; return items.keys.sorted() }
    public func deleteAll() throws { lock.lock(); defer { lock.unlock() }; items.removeAll() }
}
