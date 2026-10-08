import SwiftUI
import StorySoundsCore

/// Actions that need an explicit second step. The SAFE option (Cancel) always has the default focus.
enum ParentDataAction: Hashable {
    case resetProgress, deleteEverything, restoreBackup, deleteBackupCopy

    var title: String {
        switch self {
        case .resetProgress: return "Reset progress?"
        case .deleteEverything: return "Delete everything?"
        case .restoreBackup: return "Restore from iCloud?"
        case .deleteBackupCopy: return "Delete the iCloud copy?"
        }
    }
    func message(nickname: String) -> String {
        switch self {
        case .resetProgress:
            return "This clears \(nickname)'s sound progress, sessions and stickers so they start again. The profile and settings stay. A backup already in iCloud is not changed. It cannot be undone."
        case .deleteEverything:
            return "This removes all learning data and settings from this Apple TV and asks iCloud to delete the backup copy (iCloud finishes this when it can). It cannot be undone."
        case .restoreBackup:
            return "This brings back the progress saved in iCloud. Progress saved there replaces matching progress on this Apple TV."
        case .deleteBackupCopy:
            return "This removes the progress copy stored in iCloud. Data on this Apple TV is not touched."
        }
    }
    var confirmLabel: String {
        switch self {
        case .resetProgress: return "Yes, reset progress"
        case .deleteEverything: return "Yes, delete everything"
        case .restoreBackup: return "Yes, restore"
        case .deleteBackupCopy: return "Yes, delete the copy"
        }
    }
}

/// Step two of a risky action: Cancel (default focus, on the left) or Confirm.
struct ParentConfirmView: View {
    let action: ParentDataAction
    let nickname: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    init(action: ParentDataAction, nickname: String, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.action = action; self.nickname = nickname; self.onConfirm = onConfirm; self.onCancel = onCancel
    }
    @FocusState private var focus: Choice?
    private enum Choice: Hashable { case cancel, confirm }

    var body: some View {
        VStack(spacing: 36) {
            Image(systemName: "exclamationmark.triangle.fill").font(Theme.iconLargeFont)
            Text(action.title).font(Theme.titleFont).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(action.message(nickname: nickname)).font(Theme.bodyFont).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 1400)
            HStack(spacing: 40) {
                Button(action: onCancel) {
                    Label("No, keep things as they are", systemImage: "xmark").font(Theme.bodyFont)
                }
                .buttonStyle(FocusCardStyle(prominent: true))
                .focused($focus, equals: .cancel)
                .a11yID("parent.data.cancel")
                .accessibilityLabel("Cancel. Keep things as they are.")
                Button(action: onConfirm) {
                    Label(action.confirmLabel, systemImage: "checkmark").font(Theme.bodyFont)
                }
                .buttonStyle(FocusCardStyle())
                .focused($focus, equals: .confirm)
                .a11yID("parent.data.confirm")
                .accessibilityLabel(action.confirmLabel)
                .accessibilityHint("This cannot be undone.")
            }
            .focusSection()
        }
        .screenContainer()
        .defaultFocus($focus, .cancel)
        .onAppear { focus = .cancel }
        .onExitCommand(perform: onCancel)
    }
}

/// Result of an action, with a single OK button.
struct ParentOutcomeView: View {
    let text: String
    let onOK: () -> Void
    init(text: String, onOK: @escaping () -> Void) { self.text = text; self.onOK = onOK }
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 40) {
            Text(text).font(Theme.headingFont).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 1400)
                .a11yID("parent.data.outcome")
            Button(action: onOK) { Text("OK").font(Theme.bodyFont).frame(minWidth: 200) }
                .buttonStyle(FocusCardStyle(prominent: true))
                .focused($focused)
                .a11yID("parent.data.ok")
                .accessibilityLabel("OK")
        }
        .screenContainer()
        .defaultFocus($focused, true)
        .onAppear { focused = true }
        .onExitCommand(perform: onOK)
    }
}
