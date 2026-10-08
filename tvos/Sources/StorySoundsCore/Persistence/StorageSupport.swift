import Foundation

/// Errors surfaced by persistence, backup and deletion code. Nothing here is swallowed silently:
/// callers (and the parent area) are expected to show a calm, non-technical message.
public enum StorageError: Error, Equatable {
    /// The backing store refused or lost a write (e.g. quota exceeded).
    case writeFailed(key: String)
    /// A write appeared to succeed but reading it back did not return the same bytes.
    case verificationFailed(key: String)
    /// Encoded data exceeds the configured budget.
    case tooLarge(bytes: Int, budget: Int)
    /// Stored bytes could not be decoded.
    case corrupt(String)
    /// Stored data was written by a newer app version than this build understands.
    case newerSchema(found: Int, supported: Int)
    case notFound
    /// iCloud backup was requested but the parent has not opted in.
    case notOptedIn
    /// iCloud (or another backing service) is not available on this device/account.
    case unavailable
    case unsupportedBackupFormat
}

/// Minimal key -> Data abstraction used by the learner store, privacy settings and iCloud backup.
/// Production implementations: `UserDefaultsKeyValueStore`, `ICloudKeyValueStore`.
/// Test implementation: `InMemoryKeyValueStore` (can simulate quota / failures).
public protocol KeyValueStoring: AnyObject {
    func data(forKey key: String) -> Data?
    /// Pass `nil` to remove. Must throw if the write could not be confirmed.
    func setData(_ data: Data?, forKey key: String) throws
    func allKeys() -> [String]
}

/// Key naming. Everything the app persists starts with `root`, so "delete everything" can sweep by prefix.
public enum StorageNamespace {
    public static let root = "storysounds."

    /// Percent-encodes arbitrary text so it is safe inside a dot-separated key.
    static func token(_ raw: String) -> String {
        raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "_"
    }
    static func untoken(_ t: String) -> String { t.removingPercentEncoding ?? t }
    /// `nil` scope uses the token "_" (which can never equal an encoded value, because "_" itself would be encoded).
    static func scopeToken(_ scope: String?) -> String { scope.map(token) ?? "_" }
}

/// UserDefaults-backed key-value store. Writes are read back and verified.
///
/// LIMIT OF THAT VERIFICATION: `defaults.data(forKey:)` is answered from the in-process cache, so the read-back proves the write
/// was accepted, NOT that it reached disk. A write the system later drops (quota, termination before the flush) still passes.
/// Do not treat it as proof of durability; keep total usage small (see `SnapshotCompactor`) and rely on the scene-leaves-foreground
/// flush and on decoding the data again after the next launch.
/// tvOS note: UserDefaults is the only durable app-writable local storage on tvOS (documented ~500 KB limit).
public final class UserDefaultsKeyValueStore: KeyValueStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func data(forKey key: String) -> Data? { defaults.data(forKey: key) }

    public func setData(_ data: Data?, forKey key: String) throws {
        if let data = data {
            defaults.set(data, forKey: key)
            guard defaults.data(forKey: key) == data else { throw StorageError.verificationFailed(key: key) }
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    public func allKeys() -> [String] { Array(defaults.dictionaryRepresentation().keys) }
}

#if canImport(Darwin)
/// NSUbiquitousKeyValueStore adapter (iCloud key-value storage, ~1 MB total, needs the iCloud KVS entitlement).
public final class ICloudKeyValueStore: KeyValueStoring, @unchecked Sendable {
    private let store: NSUbiquitousKeyValueStore
    public init(store: NSUbiquitousKeyValueStore = .default) { self.store = store }

    public func data(forKey key: String) -> Data? { store.data(forKey: key) }

    public func setData(_ data: Data?, forKey key: String) throws {
        if let data = data { store.set(data, forKey: key) } else { store.removeObject(forKey: key) }
        _ = store.synchronize()
        guard store.data(forKey: key) == data else { throw StorageError.verificationFailed(key: key) }
    }

    public func allKeys() -> [String] { Array(store.dictionaryRepresentation.keys) }

    /// True when an iCloud account is signed in on this device.
    public static var isICloudAccountAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }
}
#endif

/// In-memory store for tests. Can simulate a byte quota, hard failures and silently dropped writes.
public final class InMemoryKeyValueStore: KeyValueStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    /// Total bytes allowed across all values; exceeding it makes `setData` throw `.writeFailed`.
    public var quotaBytes: Int?
    /// When it returns true for a key, `setData` throws `.writeFailed` (no change made).
    public var failWrites: ((String) -> Bool)?
    /// When it returns true for a key, the write is silently dropped (simulates a store that lies).
    public var silentlyDropWrites: ((String) -> Bool)?

    public init(quotaBytes: Int? = nil) { self.quotaBytes = quotaBytes }

    public func data(forKey key: String) -> Data? { lock.lock(); defer { lock.unlock() }; return storage[key] }

    public func setData(_ data: Data?, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard let data = data else { storage[key] = nil; return }
        if failWrites?(key) == true { throw StorageError.writeFailed(key: key) }
        if silentlyDropWrites?(key) == true { return }
        if let quota = quotaBytes {
            let others = storage.filter { $0.key != key }.reduce(0) { $0 + $1.value.count }
            if others + data.count > quota { throw StorageError.writeFailed(key: key) }
        }
        storage[key] = data
    }

    public func allKeys() -> [String] { lock.lock(); defer { lock.unlock() }; return Array(storage.keys) }
    public var totalBytes: Int { lock.lock(); defer { lock.unlock() }; return storage.values.reduce(0) { $0 + $1.count } }
}

/// Shared JSON configuration. Dates use Foundation's default (exact Double) so round-trips are lossless.
public enum SnapshotCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(value)
    }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}
