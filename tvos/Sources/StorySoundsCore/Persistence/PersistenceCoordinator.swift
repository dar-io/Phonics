import Foundation

/// Debounced, compacting writer. Call `update(_:)` after every meaningful change (cheap); the latest snapshot is
/// compacted and saved after `debounceInterval` of quiet. Call `flushNow()` synchronously when the scene becomes
/// `.inactive` / `.background` so nothing is lost if tvOS suspends or terminates the app.
///
/// All work and callbacks run on an internal serial queue. Do not call `flushNow()` from inside `onError`/`onSaved`.
public final class PersistenceCoordinator: @unchecked Sendable {
    public struct SaveReport: Sendable {
        public let profileId: String
        public let bytes: Int
        public let fitBudget: Bool
        public let attemptsDropped: Int
    }

    private let store: LearnerStore
    private let compactor: SnapshotCompactor
    private let debounceInterval: TimeInterval
    private let queue: DispatchQueue
    private var pending: LearnerSnapshot?
    private var token = 0
    private var _lastError: Error?

    /// Called on the internal queue after a failed save. The pending snapshot is kept so a later `flushNow()` retries.
    public var onError: ((Error) -> Void)?
    /// Called on the internal queue after a successful save.
    public var onSaved: ((SaveReport) -> Void)?

    public init(store: LearnerStore, compactor: SnapshotCompactor = SnapshotCompactor(), debounceInterval: TimeInterval = 2.0,
                queue: DispatchQueue = DispatchQueue(label: "storysounds.persistence")) {
        self.store = store; self.compactor = compactor; self.debounceInterval = debounceInterval; self.queue = queue
    }

    public func update(_ snapshot: LearnerSnapshot) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.pending = snapshot
            self.token += 1
            let mine = self.token
            self.queue.asyncAfter(deadline: .now() + self.debounceInterval) { [weak self] in
                guard let self = self, self.token == mine else { return }
                self.performSave()
            }
        }
    }

    /// Saves any pending snapshot immediately and waits for completion.
    public func flushNow() {
        queue.sync {
            token += 1
            performSave()
        }
    }

    /// Discards a pending, unsaved snapshot (e.g. after the profile was deleted).
    public func cancelPending() {
        queue.sync { token += 1; pending = nil }
    }

    public var hasPendingChanges: Bool { queue.sync { pending != nil } }
    public var lastError: Error? { queue.sync { _lastError } }

    private func performSave() {
        guard let snap = pending else { return }
        let result = compactor.compact(snap)
        do {
            try store.save(result.snapshot)
            pending = nil
            _lastError = nil
            onSaved?(SaveReport(profileId: snap.profile.id, bytes: result.encodedBytes, fitBudget: result.fitsBudget,
                                attemptsDropped: result.attemptsDropped))
        } catch {
            _lastError = error
            onError?(error)
        }
    }
}
