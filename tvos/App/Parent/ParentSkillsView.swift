import SwiftUI
import StorySoundsCore

/// Skills: every curriculum step with the reason for its state, five per page, grouped by four filters.
/// Selecting a row opens a detail screen with "Practise this next" / "Unlock this sound".
@MainActor
struct ParentSkillsView: View {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    @EnvironmentObject var env: AppEnvironment
    @State private var category: Category = .next
    @State private var page = 0
    @State private var selected: String?
    @State private var lastSelected: String?
    @FocusState private var rowFocus: String?

    private static let perPage = 5

    enum Category: String, CaseIterable {
        case next, learning, review, secure
        var title: String {
            switch self {
            case .next: return "Next up"
            case .learning: return "Learning"
            case .review: return "Review"
            case .secure: return "Secure"
            }
        }
        func includes(_ s: UnitStatus) -> Bool {
            switch self {
            case .next: return s == .available || s == .locked
            case .learning: return s == .inProgress
            case .review: return s == .reviewDue
            case .secure: return s == .mastered
            }
        }
    }

    var body: some View {
        if let id = selected, let unit = env.index.unit(id: id) {
            detail(unit)
        } else {
            list
        }
    }

    // MARK: List

    private var list: some View {
        let all = env.explainUnits()
        let counts = Dictionary(uniqueKeysWithValues: Category.allCases.map { c in (c, all.filter { c.includes($0.status) }.count) })
        let rows = all.filter { category.includes($0.status) }
        let pages = ParentFormat.pageCount(items: rows.count, perPage: Self.perPage)
        let visible = ParentFormat.slice(rows, page: min(page, pages - 1), perPage: Self.perPage)
        return ParentPageScaffold(title: "Skills", pageTitle: category.title, idPrefix: "parent.skills",
                                  page: $page, pageCount: pages, pagerIsDefault: false, onBack: onClose) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    ForEach(Category.allCases, id: \.self) { c in
                        Button { category = c; page = 0 } label: {
                            HStack(spacing: 8) {
                                if c == category { Image(systemName: "checkmark") }
                                Text("\(c.title) \(counts[c] ?? 0)").lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .font(Theme.captionFont).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ParentRowStyle(prominent: c == category))
                        .a11yID("parent.skills.cat.\(c.rawValue)")
                        .accessibilityLabel("\(c.title), \(counts[c] ?? 0) skills")
                        .accessibilityValue(c == category ? "Selected" : "")
                    }
                }
                .focusSection()
                if rows.isEmpty {
                    Text(emptyText).font(Theme.bodyFont).foregroundStyle(Theme.textSecondary).padding(.top, 20)
                }
                ForEach(0..<visible.count, id: \.self) { i in
                    row(index: i, visible[i])
                }
            }
        }
        .onChange(of: category) { _, _ in page = 0 }
    }

    private var emptyText: String {
        switch category {
        case .next: return "Everything available is already under way."
        case .learning: return "No sounds are being learned right now."
        case .review: return "Nothing is due for review."
        case .secure: return "No sounds are secure yet. That is normal early on."
        }
    }

    private func row(index: Int, _ e: UnitExplanation) -> some View {
        let unit = env.index.unit(id: e.unitId)
        let name = unit.map { "\($0.order). \(ParentFormat.label($0))" } ?? e.unitId
        return Button { lastSelected = e.unitId; selected = e.unitId } label: {
            HStack(spacing: 18) {
                Image(systemName: e.status.parentSymbol).font(.system(size: 36)).frame(width: 48)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(Theme.bodyFont).bold().lineLimit(1).minimumScaleFactor(0.7)
                    Text(e.reason).font(Theme.captionFont).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 8)
                Text(e.status.parentWord).font(Theme.captionFont).bold()
            }
        }
        .buttonStyle(ParentRowStyle())
        .focused($rowFocus, equals: e.unitId)
        .a11yID("parent.skills.row.\(index)")
        .accessibilityLabel("\(name), \(e.status.parentWord)")
        .accessibilityHint("\(e.reason) Press Select for details.")
    }

    // MARK: Detail

    private func detail(_ unit: GraphemeUnit) -> some View {
        let e = env.explainUnits().first { $0.unitId == unit.id }
        let status = e?.status ?? .available
        let marked = ParentPracticeActions.isMarked(unit.id, snapshot: env.snapshot)
        let actionTitle = marked ? "Stop extra practice" : (status == .locked ? "Unlock this sound" : "Practise this next")
        return ParentPageScaffold(title: ParentFormat.label(unit), pageTitle: "\(status.parentWord): why", idPrefix: "parent.skills.detail",
                                  page: .constant(0), pageCount: 1, pagerIsDefault: false, backLabel: "Back to list",
                                  onBack: closeDetail) {
            VStack(alignment: .leading, spacing: 18) {
                Label(e?.reason ?? "", systemImage: status.parentSymbol).font(Theme.bodyFont)
                    .fixedSize(horizontal: false, vertical: true)
                if !unit.exampleWords.isEmpty {
                    Text("Example words: " + unit.exampleWords.prefix(6).joined(separator: ", "))
                        .font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
                }
                ForEach(Array(unit.misconceptions.prefix(2).enumerated()), id: \.offset) { _, m in
                    Text("Easy to mix up with '\(m.confusedWith)': \(m.guidance)")
                        .font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
                        .lineLimit(2).minimumScaleFactor(0.8)
                }
                Button {
                    if marked { ParentPracticeActions.unmark(unit.id, env: env) }
                    else { ParentPracticeActions.mark(unit.id, status: status, env: env) }
                } label: {
                    Text(actionTitle).font(Theme.bodyFont).bold().frame(maxWidth: .infinity)
                }
                .buttonStyle(ParentRowStyle(prominent: true))
                .a11yID("parent.skills.detail.action")
                .accessibilityLabel(actionTitle)
                .accessibilityHint("Changes what is chosen next. Does not change progress.")
            }
        }
    }

    private func closeDetail() {
        selected = nil
        DispatchQueue.main.async { rowFocus = lastSelected }
    }
}
