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

    private static let titles = ["Where your data lives", "Progress summary", "iCloud backup", "Reset or delete"]

    var body: some View {
        if let text = outcome {
            ParentOutcomeView(text: text) {
                outcome = nil
                if returnToOnboarding { returnToOnboarding = false; env.route = .onboarding }
            }
        } else if let action = pending {
            ParentConfirmView(action: action, nickname: env.snapshot.profile.nickname,
                              onConfirm: { run(action) }, onCancel: { pending = nil })
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
            Button { pending = .resetProgress } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Reset progress", systemImage: "arrow.counterclockwise").font(Theme.bodyFont).bold()
                    Text("Start the sounds again. Keeps the profile and settings.").font(Theme.captionFont)
                }
            }
            .buttonStyle(ParentRowStyle())
            .a11yID("parent.data.reset")
            .accessibilityLabel("Reset progress")
            .accessibilityHint("Asks for confirmation. Keeps the profile and settings.")
            Button { pending = .deleteEverything } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Delete everything", systemImage: "trash").font(Theme.bodyFont).bold()
                    Text("Removes all data from this Apple TV and the iCloud copy.").font(Theme.captionFont)
                }
            }
            .buttonStyle(ParentRowStyle())
            .a11yID("parent.data.delete")
            .accessibilityLabel("Delete everything")
            .accessibilityHint("Asks for confirmation. Removes all data and any iCloud copy.")
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
        else if let d = b.lastBackupAt ?? b.latestBackup?.createdAt { status = "Last backup: \(ParentFormat.shortDate(d))." }
        else if on { status = "On. No backup made yet." }
        return VStack(alignment: .leading, spacing: 16) {
            Text(status).font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
            ParentToggleRow(title: "iCloud backup", hint: "Saves progress only (no names). Restore it on a new Apple TV.",
                      isOn: on, id: "parent.data.backup.toggle") {
                attempt("Could not change the backup setting.") { try b.setOptedIn(!on) }
            }
            Button { attempt("Backup did not work.") { try b.backUpNow() } } label: {
                Label("Back up now", systemImage: "icloud.and.arrow.up").font(Theme.bodyFont)
            }
            .buttonStyle(ParentRowStyle())
            .a11yID("parent.data.backup.now")
            .accessibilityLabel(on ? "Back up now" : "Back up now. Turn iCloud backup on first.")
            Button { pending = .restoreBackup } label: {
                Label("Restore from iCloud", systemImage: "icloud.and.arrow.down").font(Theme.bodyFont)
            }
            .buttonStyle(ParentRowStyle())
            .a11yID("parent.data.backup.restore")
            .accessibilityLabel("Restore from iCloud")
            .accessibilityHint("Asks for confirmation first.")
            Button { pending = .deleteBackupCopy } label: {
                Label("Delete the iCloud copy", systemImage: "icloud.slash").font(Theme.bodyFont)
            }
            .buttonStyle(ParentRowStyle())
            .a11yID("parent.data.backup.delete")
            .accessibilityLabel("Delete the iCloud copy")
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
            do {
                try env.deleteEverything()
                ParentGateView.clearStoredLockout()
                returnToOnboarding = true
                outcome = "Everything has been deleted from this Apple TV and from iCloud."
            } catch {
                outcome = "Something went wrong, so not everything may have been deleted. Please try again."
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
            if outcome == nil { outcome = "The iCloud copy has been deleted." }
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
