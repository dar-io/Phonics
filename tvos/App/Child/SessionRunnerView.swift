import SwiftUI
import StorySoundsCore

/// A calm "Take a break?" / "Skip?" confirmation. Pressing Menu inside it means "keep going".
/// Nothing here ever penalises the child.
@MainActor
struct ConfirmOverlay: View {
    enum Field: Hashable { case keep, leave }

    let title: String
    let message: String
    let keepTitle: String
    let leaveTitle: String
    let keepID: String
    let leaveID: String
    let onKeep: () -> Void
    let onLeave: () -> Void
    @FocusState private var focus: Field?

    var body: some View {
        ZStack {
            DimLayer()
            VStack(spacing: 28) {
                WrenView(mood: .think, size: 150)
                Text(title)
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 40) {
                    StoryButton(prominent: true, action: onKeep) {
                        Text(keepTitle).font(Theme.bodyFont)
                    }
                    .focused($focus, equals: .keep)
                    .accessibilityLabel(keepTitle)
                    .a11yID(keepID)

                    StoryButton(action: onLeave) {
                        Text(leaveTitle).font(Theme.bodyFont)
                    }
                    .focused($focus, equals: .leave)
                    .accessibilityLabel(leaveTitle)
                    .a11yID(leaveID)
                }
                .focusSection()
            }
            .padding(60)
            .frame(maxWidth: 1300)
            .background(RoundedRectangle(cornerRadius: 40).fill(Theme.surface))
            .accessibilityElement(children: .contain)
        }
        .defaultFocus($focus, Field.keep)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focus = .keep }
        }
        .onExitCommand { onKeep() }
        .accessibilityAddTraits(.isModal)
    }
}

/// Plans and tracks one practice session (about 5 to 10 minutes). All evidence is recorded by the activity
/// coordinators as the child answers; this model only sequences activities, splices in gentle recovery
/// activities after a run of misses, and writes the session summary and stickers at the end.
@MainActor
final class SessionModel: ObservableObject {
    @Published private(set) var activities: [Activity] = []
    @Published private(set) var position = 0
    @Published private(set) var isEmpty = false
    @Published private(set) var didStart = false
    private(set) var sessionId = ""
    private(set) var modelledKeys: Set<String> = []

    private var summary = SessionSummary(id: "", startedAt: Date())
    private var seed: UInt64 = 0
    private var consecutiveMisses = 0
    private var recoveries = 0
    private var masteredBefore: Set<String> = []
    private var startedAt = Date()
    private var maxSeconds: Double = 600
    private var wasFinished = false

    var current: Activity? { activities.indices.contains(position) ? activities[position] : nil }
    var total: Int { activities.count }
    var isLast: Bool { position + 1 >= activities.count }

    func start(env: AppEnvironment) {
        if didStart { return }
        didStart = true
        let when = env.now
        seed = UInt64(truncatingIfNeeded: Int64(Date().timeIntervalSince1970))
        let minutes = min(10, max(3, env.settings.mastery.sessionMinutes))
        let plan = SessionPlanner.plan(index: env.index, snapshot: env.snapshot, now: when, seed: seed,
                                       minutes: minutes, focusUnitId: nil)
        sessionId = plan.id
        activities = plan.activities
        modelledKeys = plan.modelledKeys
        summary = SessionSummary(id: plan.id, startedAt: when)
        masteredBefore = env.masteredUnitIds()
        startedAt = Date()
        maxSeconds = Double(minutes + 3) * 60
        isEmpty = plan.activities.isEmpty
    }

    /// Records the outcome of the activity that just finished. Returns false when the session is over.
    func record(_ r: ActivityResult, env: AppEnvironment) -> Bool {
        summary.activitiesDone += 1
        if !r.hadMiss && !r.startedModelled { summary.correct += 1 }
        if r.firstTryCorrect && r.support == .independent { summary.independent += 1 }
        if !summary.unitsPractised.contains(r.activity.unitId) { summary.unitsPractised.append(r.activity.unitId) }

        consecutiveMisses = r.hadMiss ? consecutiveMisses + 1 : 0
        if consecutiveMisses >= SessionPlanner.struggleThreshold && recoveries < 2 {
            let rec = SessionPlanner.recovery(index: env.index, snapshot: env.snapshot, activity: r.activity,
                                              now: env.now, seed: seed &+ UInt64(position + 1))
            activities.insert(contentsOf: rec.activities, at: position + 1)
            modelledKeys.formUnion(rec.modelledKeys)
            recoveries += 1
            consecutiveMisses = 0
        }

        position += 1
        if position >= activities.count { return false }
        if position >= 4 && Date().timeIntervalSince(startedAt) > maxSeconds { return false }
        return true
    }

    /// Writes the summary and any stickers, then flushes. Returns nil when nothing was done (no empty sessions).
    func finish(env: AppEnvironment, completed: Bool) -> SessionSummary? {
        if wasFinished { return nil }
        wasFinished = true
        guard summary.activitiesDone > 0 else { return nil }
        var s = summary
        s.endedAt = env.now
        s.completed = completed
        let after = env.masteredUnitIds()
        let counted = env.snapshot.sessions.filter { $0.completed || $0.activitiesDone >= 3 }.count
        let earned = StickerCatalog.earned(owned: env.snapshot.profile.stickers, completedSessionCount: counted,
                                           activitiesDone: s.activitiesDone, masteredBefore: masteredBefore,
                                           masteredAfter: after)
        s.stickersEarned = earned
        let finalSummary = s
        env.update { snap in
            snap.sessions.append(finalSummary)
            for id in earned where !snap.profile.stickers.contains(id) { snap.profile.stickers.append(id) }
        }
        env.flush()
        return finalSummary
    }
}

@MainActor
struct SessionRunnerView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var model = SessionModel()
    @State private var showBreak = false
    @FocusState private var emptyFocus: Bool

    var body: some View {
        ZStack {
            if model.isEmpty {
                emptyView
            } else if let activity = model.current {
                ActivityContainerView(
                    activity: activity,
                    mode: .session,
                    sessionId: model.sessionId,
                    startsModelled: model.modelledKeys.contains(activity.key),
                    env: env,
                    progressText: "Step \(model.position + 1) of \(model.total)",
                    nextLabel: model.isLast ? "All done" : "Next",
                    inputDisabled: showBreak,
                    onFinish: { result in handle(result) },
                    onMenu: { showBreak = true }
                )
                .id("\(model.position)-\(activity.key)")
                .transition(.opacity)
            } else {
                Color.clear.screenContainer()
            }

            if showBreak {
                ConfirmOverlay(
                    title: "Take a break?",
                    message: "That's okay. Your stars and stickers are safe. You can come back any time.",
                    keepTitle: "Keep playing",
                    leaveTitle: "Take a break",
                    keepID: "session.menu.continue",
                    leaveID: "session.menu.takeBreak",
                    onKeep: { showBreak = false },
                    onLeave: {
                        showBreak = false
                        endSession(completed: false)
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showBreak)
        .onAppear { model.start(env: env) }
    }

    private var emptyView: some View {
        VStack(spacing: 40) {
            Spacer()
            WrenSays(text: "You have done everything for now. Come back soon for more!", mood: .cheer)
            StoryButton(prominent: true, action: { env.route = .home }) {
                Label("Back home", systemImage: "house.fill").font(Theme.bodyFont)
            }
            .focused($emptyFocus)
            .accessibilityLabel("Back home")
            .a11yID("session.empty.home")
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .screenContainer()
        .defaultFocus($emptyFocus, true)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { emptyFocus = true } }
        .onExitCommand { env.route = .home }
    }

    private func handle(_ result: ActivityResult) {
        let more = model.record(result, env: env)
        if !more { endSession(completed: true) }
    }

    private func endSession(completed: Bool) {
        env.cancelSequence()
        if let summary = model.finish(env: env, completed: completed) {
            env.route = .summary(summary)
        } else {
            env.route = .home
        }
    }
}
