/// A stored snapshot together with the moment it was last saved (the envelope's `savedAt`).
public struct StoredSnapshot: Sendable {
    public let snapshot: LearnerSnapshot
    public let savedAt: Date
    public init(snapshot: LearnerSnapshot, savedAt: Date) { self.snapshot = snapshot; self.savedAt = savedAt }
}

public enum ProfileLoadFailureReason: Equatable, Sendable {
    case corrupt(String)
    case newerSchema(found: Int, supported: Int)
    case other(String)

    static func from(_ error: Error) -> ProfileLoadFailureReason {
        if let e = error as? StorageError {
            switch e {
            case .corrupt(let m): return .corrupt(m)
            case .newerSchema(let f, let s): return .newerSchema(found: f, supported: s)
            default: return .other("\(e)")
            }
        }
        return .other("\(error)")
    }
}

/// A profile that exists on disk but could not be read. It is NEVER deleted or overwritten by the loading helpers.
public struct ProfileLoadFailure: Equatable, Sendable {
    public let profileId: String
    public let reason: ProfileLoadFailureReason
    public init(profileId: String, reason: ProfileLoadFailureReason) { self.profileId = profileId; self.reason = reason }
}

/// Result of choosing which profile to open at launch. Nothing is silently discarded: every id that failed to load is listed.
public struct ProfileLoadOutcome: Sendable {
    /// The chosen profile (nil when there is none, or none could be read).
    public let stored: StoredSnapshot?
    /// Every profile id present in the store, sorted.
    public let profileIds: [String]
    /// Profiles that exist but failed to decode (corrupt or written by a newer app version).
    public let failures: [ProfileLoadFailure]
    /// True when the active-profile pointer named a profile that could not be used and another profile was chosen instead.
    public let activePointerWasUnusable: Bool

    public var snapshot: LearnerSnapshot? { return stored?.snapshot }
    public var hadFailures: Bool { return !failures.isEmpty }
    /// True when the store holds data but none of it could be read: the caller must NOT quietly start a new profile over it.
    public var onlyUnreadableData: Bool { return stored == nil && !failures.isEmpty }

    public init(stored: StoredSnapshot?, profileIds: [String], failures: [ProfileLoadFailure], activePointerWasUnusable: Bool = false) {
        self.stored = stored; self.profileIds = profileIds; self.failures = failures; self.activePointerWasUnusable = activePointerWasUnusable
    }
}

/// Persistence for learner snapshots, one per profile id.
public protocol LearnerStore: AnyObject, Sendable {
    /// Returns nil when nothing is stored for the profile. Throws on corrupt/newer-schema data.
    func load(profileId: String) throws -> LearnerSnapshot?
    /// Must never damage the previously saved value if it throws.
    func save(_ snapshot: LearnerSnapshot) throws
    func delete(profileId: String) throws
    func listProfileIds() throws -> [String]
    func deleteAll() throws

    /// Like `load`, but also returns when the profile was last saved. Default: `load` with `savedAt = .distantPast`.
    func loadStored(profileId: String) throws -> StoredSnapshot?
    /// The explicitly chosen active profile (survives relaunch). nil when none was ever set or it was deleted.
    /// Default: nil.
    func activeProfileId() throws -> String?
    /// Records the active profile (`nil` clears it). Throws `.notFound` for an id that is not stored.
    /// Default: throws `.unavailable` (the store does not support an active pointer).
    func setActiveProfileId(_ id: String?) throws
}

public extension LearnerStore {
    func loadStored(profileId: String) throws -> StoredSnapshot? {
        guard let s = try load(profileId: profileId) else { return nil }
        return StoredSnapshot(snapshot: s, savedAt: Date.distantPast)
    }
    func activeProfileId() throws -> String? { return nil }
    func setActiveProfileId(_ id: String?) throws { throw StorageError.unavailable }

    /// The newest-saved profile that decodes. Corrupt / newer-schema profiles are reported in `failures` and left untouched.
    /// Ties on `savedAt` are broken by profile id so the choice is deterministic.
    func loadMostRecentValid() throws -> ProfileLoadOutcome {
        return try chooseProfile(preferring: nil)
    }

    /// Launch policy: the explicit active profile when it loads, otherwise the most recent valid one.
    func loadActiveOrMostRecentValid() throws -> ProfileLoadOutcome {
        let active: String? = try? activeProfileId()
        return try chooseProfile(preferring: active)
    }

    private func chooseProfile(preferring active: String?) throws -> ProfileLoadOutcome {
        let ids: [String] = try listProfileIds()
        var failures: [ProfileLoadFailure] = []
        var valid: [(id: String, stored: StoredSnapshot)] = []
        var activeUnusable = false
        for id in ids {
            do {
                if let st = try loadStored(profileId: id) { valid.append((id: id, stored: st)) }
            } catch {
                failures.append(ProfileLoadFailure(profileId: id, reason: ProfileLoadFailureReason.from(error)))
            }
        }
        if let a = active {
            if let hit = valid.first(where: { $0.id == a }) {
                return ProfileLoadOutcome(stored: hit.stored, profileIds: ids, failures: failures)
            }
            activeUnusable = true
        }
        let sorted = valid.sorted { (x, y) -> Bool in
            if x.stored.savedAt != y.stored.savedAt { return x.stored.savedAt > y.stored.savedAt }
            return x.id < y.id
        }
        return ProfileLoadOutcome(stored: sorted.first?.stored, profileIds: ids, failures: failures, activePointerWasUnusable: activeUnusable)
    }
}

/// Core store over any `KeyValueStoring`.
///
/// Key layout (all under `storysounds.learner.<scope>.`):
/// - `snap.<profile>.<generation>`: envelope bytes (JSON)
/// - `ptr.<profile>`: current generation number
/// - `active`: the id of the explicitly chosen active profile
///
/// Save = write a NEW generation key, verify it by reading back, flip the pointer, then delete EVERY other generation of
/// that profile (not just the previous one, so generations orphaned by a crash between the flip and the delete are reclaimed
/// on the next save). `load` and `listProfileIds` also reclaim stale generations and snapshot keys that no pointer references.
///
/// STORAGE BUDGET: tvOS UserDefaults is documented as ~500 KB in total. The old and the new generation briefly coexist,
/// so peak use is about 2x one snapshot; the defaults (`SnapshotCompactor` 150 KB, `defaultMaxBytes` 200 KB) keep that peak
/// under ~400 KB.
///
/// DURABILITY LIMIT (cannot be fixed here): the read-back after a write goes through the same in-process cache that just
/// accepted the write (`UserDefaults.data(forKey:)`), so it proves the write was ACCEPTED, not that it reached disk. A write the
/// system later discards still passes. Only reading the data back after a relaunch proves durability; the app therefore also
/// flushes when the scene leaves the foreground, and loading never trusts a pointer whose data fails to decode.
public final class KeyValueLearnerStore: LearnerStore, @unchecked Sendable {
    public static let defaultMaxBytes = 200_000

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
    private var activeKey: String { prefix + "active" }

    private func generation(_ pid: String) -> Int? {
        guard let d = kv.data(forKey: pointerKey(pid)), let s = String(data: d, encoding: .utf8) else { return nil }
        return Int(s)
    }

    /// Removes every generation of `pid` except `keep`. Best effort: a failure is retried on the next save/load.
    @discardableResult
    private func sweepStale(_ pid: String, keep: Int) -> Int {
        let sp = snapPrefix(pid)
        let keepKey = snapKey(pid, keep)
        var removed = 0
        for k in kv.allKeys() where k.hasPrefix(sp) && k != keepKey {
            if (try? kv.setData(nil, forKey: k)) != nil { removed += 1 }
        }
        return removed
    }

    /// Removes snapshot keys whose profile has no pointer (left behind by a crash during `delete`), and keys of the
    /// wrong shape. Pointers themselves are never touched.
    @discardableResult
    private func reclaimOrphansLocked() -> Int {
        let ptrPrefix = prefix + "ptr."
        let snapP = prefix + "snap."
        var live = Set<String>()
        for k in kv.allKeys() where k.hasPrefix(ptrPrefix) { live.insert(String(k.dropFirst(ptrPrefix.count))) }
        var removed = 0
        for k in kv.allKeys() where k.hasPrefix(snapP) {
            let rest = String(k.dropFirst(snapP.count))
            let token = rest.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            if !live.contains(token) {
                if (try? kv.setData(nil, forKey: k)) != nil { removed += 1 }
            }
        }
        return removed
    }

    /// Reclaims orphaned snapshot keys now. Returns how many keys were removed.
    @discardableResult
    public func reclaimOrphans() -> Int {
        lock.lock(); defer { lock.unlock() }
        return reclaimOrphansLocked()
    }

    public func load(profileId: String) throws -> LearnerSnapshot? {
        return try loadStored(profileId: profileId)?.snapshot
    }

    public func loadStored(profileId: String) throws -> StoredSnapshot? {
        lock.lock(); defer { lock.unlock() }
        guard let gen = generation(profileId) else { return nil }
        guard let data = kv.data(forKey: snapKey(profileId, gen)) else { throw StorageError.corrupt("pointer without data") }
        let envelope = try migrator.decodeEnvelope(from: data).envelope
        sweepStale(profileId, keep: gen)
        return StoredSnapshot(snapshot: envelope.snapshot, savedAt: envelope.savedAt)
    }

    public func save(_ snapshot: LearnerSnapshot) throws {
        lock.lock(); defer { lock.unlock() }
        let pid = snapshot.profile.id
        let envelope = SnapshotEnvelope(savedAt: clock(), snapshot: snapshot)
        let data = try SnapshotCodec.encode(envelope)
        guard data.count <= maxBytes else { throw StorageError.tooLarge(bytes: data.count, budget: maxBytes) }

        let oldGen = generation(pid)
        // Never reuse a generation number that is still on disk (an orphan from an earlier crash could be higher than the pointer).
        var highest = oldGen ?? 0
        let sp = snapPrefix(pid)
        for k in kv.allKeys() where k.hasPrefix(sp) {
            if let g = Int(k.dropFirst(sp.count)), g > highest { highest = g }
        }
        let newGen = highest + 1
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
        // The new generation is live: reclaim the previous one and any orphans.
        sweepStale(pid, keep: newGen)
    }

    public func delete(profileId: String) throws {
        lock.lock(); defer { lock.unlock() }
        try deleteLocked(profileId)
    }

    private func deleteLocked(_ pid: String) throws {
        // Remove the pointer first so the profile disappears even if a data key removal were to fail.
        try kv.setData(nil, forKey: pointerKey(pid))
        if let d = kv.data(forKey: activeKey), String(data: d, encoding: .utf8) == pid { try kv.setData(nil, forKey: activeKey) }
        let sp = snapPrefix(pid)
        for k in kv.allKeys() where k.hasPrefix(sp) { try kv.setData(nil, forKey: k) }
    }

    public func listProfileIds() throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        reclaimOrphansLocked()
        let p = prefix + "ptr."
        return kv.allKeys().filter { $0.hasPrefix(p) }
            .map { StorageNamespace.untoken(String($0.dropFirst(p.count))) }.sorted()
    }

    public func activeProfileId() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let d = kv.data(forKey: activeKey), let s = String(data: d, encoding: .utf8), !s.isEmpty else { return nil }
        // A pointer to a profile that no longer exists is treated as unset.
        return kv.data(forKey: pointerKey(s)) == nil ? nil : s
    }

    public func setActiveProfileId(_ id: String?) throws {
        lock.lock(); defer { lock.unlock() }
        guard let id = id else { try kv.setData(nil, forKey: activeKey); return }
        guard kv.data(forKey: pointerKey(id)) != nil else { throw StorageError.notFound }
        let d = Data(id.utf8)
        try kv.setData(d, forKey: activeKey)
        guard kv.data(forKey: activeKey) == d else { throw StorageError.verificationFailed(key: activeKey) }
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
    public func loadStored(profileId: String) throws -> StoredSnapshot? { try inner.loadStored(profileId: profileId) }
    public func activeProfileId() throws -> String? { try inner.activeProfileId() }
    public func setActiveProfileId(_ id: String?) throws { try inner.setActiveProfileId(id) }
    @discardableResult public func reclaimOrphans() -> Int { inner.reclaimOrphans() }
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
    private var savedAts: [String: Date] = [:]
    private var active: String?
    private let clock: () -> Date
    /// If set, `save` throws this error (and leaves previous data untouched).
    public var saveError: Error?
    public private(set) var saveCount = 0

    public init(clock: @escaping () -> Date = { Date() }) { self.clock = clock }

    public func load(profileId: String) throws -> LearnerSnapshot? { lock.lock(); defer { lock.unlock() }; return items[profileId] }
    public func loadStored(profileId: String) throws -> StoredSnapshot? {
        lock.lock(); defer { lock.unlock() }
        guard let s = items[profileId] else { return nil }
        return StoredSnapshot(snapshot: s, savedAt: savedAts[profileId] ?? Date.distantPast)
    }
    public func save(_ snapshot: LearnerSnapshot) throws {
        lock.lock(); defer { lock.unlock() }
        if let e = saveError { throw e }
        saveCount += 1
        items[snapshot.profile.id] = snapshot
        savedAts[snapshot.profile.id] = clock()
    }
    public func delete(profileId: String) throws {
        lock.lock(); defer { lock.unlock() }
        items[profileId] = nil; savedAts[profileId] = nil
        if active == profileId { active = nil }
    }
    public func listProfileIds() throws -> [String] { lock.lock(); defer { lock.unlock() }; return items.keys.sorted() }
    public func deleteAll() throws { lock.lock(); defer { lock.unlock() }; items.removeAll(); savedAts.removeAll(); active = nil }
    public func activeProfileId() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        if let a = active, items[a] != nil { return a }
        return nil
    }
    public func setActiveProfileId(_ id: String?) throws {
        lock.lock(); defer { lock.unlock() }
        guard let id = id else { active = nil; return }
        guard items[id] != nil else { throw StorageError.notFound }
        active = id
    }
}
