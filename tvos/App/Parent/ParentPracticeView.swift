import SwiftUI
import StorySoundsCore

/// Parent overrides ("Practise this next"). These only add/remove `ParentOverride` entries via `env.update`;
/// `SkillState` evidence is never touched (Progression only reads overrides to explain and to choose what comes next).
@MainActor
enum ParentPracticeActions {
    static func isMarked(_ unitId: String, snapshot: LearnerSnapshot) -> Bool {
        Progression.revisitUnitIds(snapshot).contains(unitId)
    }
    /// A locked unit is unlocked; any other unit is marked for extra practice.
    static func mark(_ unitId: String, status: UnitStatus, env: AppEnvironment) {
        let mode: OverrideMode = status == .locked ? .unlocked : .revisit
        let when = Date()
        env.update { snap in snap.profile.overrides.append(ParentOverride(unitId: unitId, mode: mode, at: when)) }
    }
    static func unmark(_ unitId: String, env: AppEnvironment) {
        env.update { snap in snap.profile.overrides.removeAll(where: { $0.unitId == unitId }) }
    }
}

/// Today's practice: a five-minute idea from the report, and an optional "Practise this next".
@MainActor
struct ParentPracticeView: View {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    @EnvironmentObject var env: AppEnvironment
    @State private var page = 0
    @State private var message: String?

    private static let titles = ["Five minutes together", "Practise this next"]

    var body: some View {
        ParentPageScaffold(title: "Today's practice", pageTitle: Self.titles[page], idPrefix: "parent.practice",
                           page: $page, pageCount: Self.titles.count, pagerIsDefault: page == 0, onBack: onClose) {
            if page == 0 { plan } else { candidates }
        }
    }

    private var plan: some View {
        let steps = env.parentReport().suggestedPracticeSteps
        return VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(steps.prefix(5).enumerated()), id: \.offset) { i, s in
                HStack(alignment: .top, spacing: 18) {
                    Text("\(i + 1).").font(Theme.bodyFont).bold().foregroundStyle(Theme.accent)
                    Text(s).font(Theme.bodyFont).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            Text("Short and cheerful works best. Stop when your child has had enough.")
                .font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
        }
    }

    private var candidateIds: [String] {
        let report = env.parentReport()
        var ids: [String] = []
        if let c = report.currentPosition { ids.append(c.id) }
        for r in report.dueForReview.prefix(2) where !ids.contains(r.id) { ids.append(r.id) }
        return Array(ids.prefix(3))
    }

    private var candidates: some View {
        let explained = Dictionary(env.explainUnits().map { ($0.unitId, $0) }, uniquingKeysWith: { a, _ in a })
        return VStack(alignment: .leading, spacing: 18) {
            Text("Pick a sound to come up soon. This only changes what is chosen next; your child's progress is not changed.")
                .font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
            if candidateIds.isEmpty {
                Text("Nothing to suggest yet. Play a session first.").font(Theme.bodyFont)
            }
            ForEach(Array(candidateIds.enumerated()), id: \.offset) { i, id in
                candidateRow(index: i, unitId: id, explanation: explained[id])
            }
            if let m = message {
                Text(m).font(Theme.captionFont).foregroundStyle(Theme.positive)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private func candidateRow(index: Int, unitId: String, explanation: UnitExplanation?) -> some View {
        let name = env.index.unit(id: unitId).map { ParentFormat.label($0) } ?? unitId
        let marked = ParentPracticeActions.isMarked(unitId, snapshot: env.snapshot)
        let status = explanation?.status ?? .available
        let verb = marked ? "Stop extra practice for" : (status == .locked ? "Unlock and practise" : "Practise this next:")
        return Button {
            if marked {
                ParentPracticeActions.unmark(unitId, env: env)
                message = "Done. \(name) is back to normal."
            } else {
                ParentPracticeActions.mark(unitId, status: status, env: env)
                message = "Saved. \(name) will come up in the next session."
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(verb) \(name)").font(Theme.bodyFont).bold().lineLimit(2)
                Text(marked ? "Marked for extra practice" : (explanation?.reason ?? "")).font(Theme.captionFont)
                    .lineLimit(2)
            }
        }
        .buttonStyle(ParentRowStyle())
        .a11yID("parent.practice.next.\(index)")
        .accessibilityLabel("\(verb) \(name)")
        .accessibilityHint("Changes what is chosen next. Does not change progress.")
    }
}
