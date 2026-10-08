import SwiftUI
import StorySoundsCore

/// Progress: where the child is, recent sessions, mix-ups, then plain-English background pages.
@MainActor
struct ParentProgressView: View {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    @EnvironmentObject var env: AppEnvironment
    @State private var page = 0

    private static let titles = [
        "Where things stand", "Recent sessions", "Sounds being mixed up",
        "Reception and Year 1 at a glance", "Phonics words explained (1 of 2)",
        "Phonics words explained (2 of 2)", "About this app",
    ]

    var body: some View {
        ParentPageScaffold(title: "Progress", pageTitle: Self.titles[page], idPrefix: "parent.progress",
                           page: $page, pageCount: Self.titles.count, onBack: onClose) {
            pageContent
        }
    }

    @ViewBuilder private var pageContent: some View {
        switch page {
        case 0: overview
        case 1: sessions
        case 2: mixUps
        case 3: ParentCurriculumGlance(index: env.index)
        case 4: ParentExplainerPage(terms: ParentExplainers.first)
        case 5: ParentExplainerPage(terms: ParentExplainers.second)
        default: ParentAboutPage()
        }
    }

    // MARK: Page 0

    private var overview: some View {
        let report = env.parentReport()
        let next = env.explainUnits().filter { $0.status != .mastered }.prefix(3)
        return VStack(alignment: .leading, spacing: 24) {
            if let c = report.currentPosition {
                Text("Now learning: \(c.label)").font(Theme.headingFont).lineLimit(2)
            } else {
                Text("No sounds started yet").font(Theme.headingFont)
            }
            HStack(spacing: 24) {
                ParentStatTile(value: report.mastered.count, label: "Secure")
                ParentStatTile(value: report.developing.count, label: "Still learning")
                ParentStatTile(value: report.dueForReview.count, label: "Due for review")
            }
            if !next.isEmpty {
                Text("Coming up").font(Theme.subheadingFont).foregroundStyle(Theme.accent)
                ForEach(Array(next), id: \.unitId) { e in
                    HStack(spacing: 16) {
                        Image(systemName: e.status.parentSymbol)
                        Text(unitName(e.unitId)).bold()
                        Text("(\(e.status.parentWord))").foregroundStyle(Theme.textSecondary)
                    }
                    .font(Theme.bodyFont)
                    .accessibilityElement(children: .combine)
                }
            }
            Text("Sessions played: \(report.totalSessions)   Stickers: \(report.stickerCount)")
                .font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
        }
    }

    private func unitName(_ id: String) -> String {
        env.index.unit(id: id).map { ParentFormat.label($0) } ?? id
    }

    // MARK: Page 1

    private var sessions: some View {
        let rows = env.parentReport().recentSessions
        return VStack(alignment: .leading, spacing: 18) {
            if rows.isEmpty {
                Text("No sessions yet. Play one short session together and it will appear here.").font(Theme.bodyFont)
            }
            ForEach(Array(rows.prefix(5).enumerated()), id: \.offset) { _, s in
                Text(sessionLine(s)).font(Theme.bodyFont).lineLimit(2)
                    .padding(.vertical, 10).padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private func sessionLine(_ s: ReportSession) -> String {
        var parts = [ParentFormat.shortDate(s.startedAt), "\(s.activitiesDone) activities"]
        if let a = s.accuracyPercent { parts.append("\(a)% right") }
        if let m = s.minutes { parts.append("about \(m) min") }
        parts.append(s.completed ? "finished" : "stopped early")
        return parts.joined(separator: " · ")
    }

    // MARK: Page 2

    private var mixUps: some View {
        let rows = env.parentReport().topConfusions
        return VStack(alignment: .leading, spacing: 14) {
            if rows.isEmpty {
                Text("Nothing stands out yet. Mix-ups show here once the same slip happens more than once.")
                    .font(Theme.bodyFont)
            }
            ForEach(Array(rows.prefix(5).enumerated()), id: \.offset) { _, c in
                VStack(alignment: .leading, spacing: 2) {
                    Text("'\(c.expected)' and '\(c.chosen)' are being mixed up (\(c.count) time\(c.count == 1 ? "" : "s"))")
                        .font(Theme.bodyFont).bold().lineLimit(2)
                    if let g = guidance(expected: c.expected, chosen: c.chosen) {
                        Text("Tip: \(g)").font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Finds the curriculum's misconception guidance for this pair, in either direction.
    private func guidance(expected: String, chosen: String) -> String? {
        let top = env.index.maxOrder
        func find(_ a: String, _ b: String) -> String? {
            for u in env.index.units where u.graphemes.contains(a) {
                for m in u.misconceptions {
                    if m.confusedWith == b || env.index.resolveGraphemes(m.confusedWith, atOrder: top).contains(b) {
                        return m.guidance
                    }
                }
            }
            return nil
        }
        return find(expected, chosen) ?? find(chosen, expected)
    }
}
