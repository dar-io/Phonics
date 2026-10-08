import SwiftUI
import StorySoundsCore

/// Your data: privacy statement, on-screen summary, opt-in iCloud backup, and two-step reset/delete.
@MainActor
struct ParentDataView: View {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.parentBackup) private var backup
    @State private var page = 0
    @State private var pending: ParentDataAction?
    @State private var outcome: String?
    /// After a successful 'delete everything' the app returns to first-launch onboarding once the grown-up taps OK.
    @State private var returnToOnboarding = false
    @State private var refresh = 0   // bumps after backup actions so the status text re-reads the controller
    /// The control that opened a confirmation, so Cancel / OK can put focus back on it.
    @State private var opener: DataControl?
    @FocusState private var dataFocus: DataControl?

    private enum DataControl: Hashable { case reset, delete, restore, deleteCopy }

    private static let titles = ["Where your data lives", "Progress summary", "iCloud backup", "Reset or delete"]

    var body: some View {
        if let text = outcome {
            ParentOutcomeView(text: text) {
                outcome = nil
                if returnToOnboarding { returnToOnboarding = false; env.route = .onboarding } else { restoreFocus() }
            }
        } else if let action = pending {
            ParentConfirmView(action: action, nickname: env.snapshot.profile.nickname,
                              onConfirm: { run(action) }, onCancel: { pending = nil; restoreFocus() })
        } else {
            ParentPageScaffold(title: "Your data", pageTitle: Self.titles[page], idPrefix: "parent.data",
                               page: $page, pageCount: Self.titles.count, onBack: onClose) {
                switch page {
                case 0: privacy
                case 1: summary
                case 2: backupPage
                default: resetPage
                }
            }
        }
    }

    /// Puts focus back on the control that opened the confirmation (best effort; the page is rebuilt first).
    private func restoreFocus() {
        guard let target = opener else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { dataFocus = target }
    }

    private func ask(_ action: ParentDataAction, from control: DataControl) {
        opener = control
        pending = action
    }

    // MARK: Pages

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(["Stored on this Apple TV only.", "No accounts and no sign-in.", "No ads.", "No analytics or tracking.",
                     "No links out of the app.", "Only a nickname is kept, never a real name."], id: \.self) { line in
                Label(line, systemImage: "checkmark.circle.fill").font(Theme.bodyFont)
            }
            Text("Apple TV cannot export files, so the on-screen summary and the optional iCloud backup are the ways to keep a record.")
                .font(Theme.captionFont).foregroundStyle(Theme.textSecondary).padding(.top, 8)
        }
    }

    private var summary: some View {
        let lines = env.parentReport().humanReadableSummary().components(separatedBy: "\n")
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                Text(l).font(Theme.captionFont).fixedSize(horizontal: false, vertical: true)
            }
        }
        .a11yID("parent.data.summary")
    }

    private var resetPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Both ask you to confirm first. Nothing happens until you say yes.").font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
            Button { ask(.resetProgress, from: .reset) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Reset progress", systemImage: "arrow.counterclockwise").font(Theme.bodyFont).bold()
                    Text("Start the sounds again. Keeps the profile and settings.").font(Theme.captionFont)
                }
            }
            .buttonStyle(ParentRowStyle())
            .focused($dataFocus, equals: .reset)
            .a11yID("parent.data.reset")
            .accessibilityLabel("Reset progress")
            .accessibilityHint("Asks for confirmation. Keeps the profile and settings.")
            Button { ask(.deleteEverything, from: .delete) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Delete everything", systemImage: "trash").font(Theme.bodyFont).bold()
                    Text("Removes all data from this Apple TV and asks iCloud to delete the backup copy.").font(Theme.captionFont)
                }
            }
            .buttonStyle(ParentRowStyle())
            .focused($dataFocus, equals: .delete)
            .a11yID("parent.data.delete")
            .accessibilityLabel("Delete everything")
            .accessibilityHint("Asks for confirmation. Removes all data from this Apple TV and asks iCloud to delete the backup copy.")
        }
    }

    // MARK: Backup

    @ViewBuilder private var backupPage: some View {
        if let b = backup {
            backupControls(b)
        } else {
            ParentInfoBlock(heading: "Not set up in this version",
                      text: "iCloud backup is not available in this build of the app, so nothing is ever sent from this Apple TV.")
        }
    }

    private func backupControls(_ b: any ParentBackupControlling) -> some View {
        _ = refresh
        let on = b.isOptedIn
        var status = "Off by default. Only learner progress is saved, with no names."
        if !b.isAvailable { status = "iCloud is not available on this Apple TV. Sign in to iCloud in Settings to use it." }
        else if let d = b.lastBackupAt ?? b.latestBackup?.createdAt {
            // Only shown when the copy was read back after writing (see ParentBackupAdapter).
            status = "Last backup: \(ParentFormat.shortDate(d))." + (on ? "" : " Backup is off, but this copy is still in iCloud.")
        }
        else if on { status = "On. No backup made yet." }
        return VStack(alignment: .leading, spacing: 16) {
            Text(status).font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
            ParentToggleRow(title: "iCloud backup", hint: "Saves progress only (no names). Turning it off does not remove a copy already in iCloud.",
                      isOn: on, id: "parent.data.backup.toggle") {
                attempt("Could not change the backup setting.") { try b.setOptedIn(!on) }
            }
            Button { attempt("Backup did not work.") { try b.backUpNow() } } label: {
                Label("Back up now", systemImage: "icloud.and.arrow.up").font(Theme.bodyFont)
            }
            .buttonStyle(ParentRowStyle())
            .a11yID("parent.data.backup.now")
            .accessibilityLabel(on ? "Back up now" : "Back up now. Turn iCloud backup on first.")
            Button { ask(.restoreBackup, from: .restore) } label: {
                Label("Restore from iCloud", systemImage: "icloud.and.arrow.down").font(Theme.bodyFont)
            }
            .buttonStyle(ParentRowStyle())
            .focused($dataFocus, equals: .restore)
            .a11yID("parent.data.backup.restore")
            .accessibilityLabel("Restore from iCloud")
            .accessibilityHint("Asks for confirmation first.")
            Button { ask(.deleteBackupCopy, from: .deleteCopy) } label: {
                Label(on ? "Delete the iCloud copy" : "Also delete the iCloud copy", systemImage: "icloud.slash")
                    .font(Theme.bodyFont)
            }
            .buttonStyle(ParentRowStyle())
            .focused($dataFocus, equals: .deleteCopy)
            .a11yID("parent.data.backup.delete")
            .accessibilityLabel(on ? "Delete the iCloud copy" : "Also delete the iCloud copy")
            .accessibilityHint("Asks for confirmation first.")
        }
    }

    /// Runs a backup-controller call; on failure shows a short, honest message.
    private func attempt(_ failure: String, _ body: () throws -> Void) {
        do { try body() } catch { outcome = "\(failure) \(Self.reason(error))" }
        refresh += 1
    }

    // MARK: Actions

    private func run(_ action: ParentDataAction) {
        pending = nil
        switch action {
        case .resetProgress:
            env.resetProgress()
            outcome = "Progress has been reset. The profile and settings were kept."
        case .deleteEverything:
            // Read before deleting: was iCloud reachable? Its removal is only queued by the system, never confirmed here.
            let icloudReachable = env.backup.isAvailable
            do {
                try env.deleteEverything()
                ParentGateView.clearStoredLockout()
                returnToOnboarding = true
                outcome = icloudReachable
                    ? "Everything has been deleted from this Apple TV. The iCloud copy was deleted too; iCloud may take a short while to finish removing it."
                    : "Everything has been deleted from this Apple TV. iCloud could not be reached, so we cannot confirm the iCloud copy is gone. If you made a backup, delete it in iCloud settings."
            } catch {
                outcome = "Something went wrong, so some data may remain on this Apple TV or in iCloud. Please try again."
            }
        case .restoreBackup:
            guard let b = backup else { outcome = "iCloud backup is not available."; return }
            do {
                let n = try b.restoreLatest()
                outcome = n > 0 ? "Restored \(n) learner profile\(n == 1 ? "" : "s") from iCloud."
                               : "The backup was read, but this Apple TV already had everything in it."
            } catch { outcome = "Could not restore. \(Self.reason(error))" }
        case .deleteBackupCopy:
            guard let b = backup else { outcome = "iCloud backup is not available."; return }
            attempt("Could not delete the iCloud copy.") { try b.deleteBackupCopy() }
            if outcome == nil {
                outcome = !b.isAvailable
                    ? "iCloud is not available right now, so we cannot confirm the copy is gone. Try again when iCloud is available."
                    : (b.latestBackup == nil
                        ? "The iCloud copy was deleted. iCloud may take a short while to finish removing it."
                        : "The copy is still showing in iCloud. Please try again.")
            }
        }
    }

    private static func reason(_ error: Error) -> String {
        guard let e = error as? StorageError else { return "Please try again." }
        switch e {
        case .notFound: return "There is no backup in iCloud yet."
        case .notOptedIn: return "Turn iCloud backup on first."
        case .unavailable: return "iCloud is not available on this Apple TV."
        case .tooLarge: return "The progress is too large to back up."
        default: return "Please try again."
        }
    }
}
