import SwiftUI
import StorySoundsCore

// NEEDS (AppEnvironment owner): AppEnvironment has no backup member in the agreed interface. The Your-data screen reads
// an OPTIONAL controller from the SwiftUI environment instead, so nothing here depends on a missing member:
//
//     ParentAreaView()
//         .environment(\.parentBackup, ParentBackupAdapter(service: backupService, privacy: privacyStore,
//                                                          snapshots: { [env.snapshot] },
//                                                          restore: { payload in /* BackupRestoration.apply(...) */ payload.snapshots.count }))
//
// When no controller is injected the screen says iCloud backup is not set up in this build and offers no backup buttons.

/// What the Your-data screen needs from the backup layer. All calls are explicit, parent-triggered actions.
@MainActor
protocol ParentBackupControlling: AnyObject {
    /// False when iCloud cannot be used (e.g. no iCloud account on this Apple TV).
    var isAvailable: Bool { get }
    /// The parent's opt-in. Default OFF.
    var isOptedIn: Bool { get }
    var lastBackupAt: Date? { get }
    var latestBackup: BackupInfo? { get }
    func setOptedIn(_ on: Bool) throws
    func backUpNow() throws
    /// Restores the latest backup; returns how many profiles were written.
    func restoreLatest() throws -> Int
    func deleteBackupCopy() throws
}

/// Ready-made adapter over the Core `BackupService` + `PrivacySettingsStore`.
@MainActor
final class ParentBackupAdapter: ParentBackupControlling {
    private let service: BackupService
    private let privacy: PrivacySettingsStore
    private let snapshots: () -> [LearnerSnapshot]
    private let restoreHandler: (BackupPayload) throws -> Int

    /// - restore: apply the payload to the learner store (e.g. `BackupRestoration.apply`) and return profiles written.
    init(service: BackupService, privacy: PrivacySettingsStore,
         snapshots: @escaping () -> [LearnerSnapshot], restore: @escaping (BackupPayload) throws -> Int) {
        self.service = service; self.privacy = privacy; self.snapshots = snapshots; self.restoreHandler = restore
    }

    var isAvailable: Bool { service.isAvailable }
    var isOptedIn: Bool { privacy.load().iCloudBackupEnabled }
    var lastBackupAt: Date? { privacy.load().lastBackupAt }
    var latestBackup: BackupInfo? { service.latestBackupInfo() }

    func setOptedIn(_ on: Bool) throws {
        var s = privacy.load()
        s.iCloudBackupEnabled = on
        try privacy.save(s)
    }
    func backUpNow() throws { _ = try service.backUp(snapshots: snapshots(), now: Date()) }
    func restoreLatest() throws -> Int { try restoreHandler(try service.restore()) }
    func deleteBackupCopy() throws { try service.deleteBackup() }
}

private struct ParentBackupKey: EnvironmentKey {
    static var defaultValue: (any ParentBackupControlling)? { nil }
}

extension EnvironmentValues {
    var parentBackup: (any ParentBackupControlling)? {
        get { self[ParentBackupKey.self] }
        set { self[ParentBackupKey.self] = newValue }
    }
}
