import SwiftUI
import StorySoundsCore

/// A short, game-like check (at most ten items, stops early) that decides where adventures start.
/// There is no score on screen and nothing is recorded as a mistake.
@MainActor
struct BaselineView: View {
    private enum Stage: Equatable { case intro, playing, outro }
    private enum IntroFocus: Hashable { case start, skip, finish }

    @EnvironmentObject private var env: AppEnvironment
    @State private var stage: Stage = .intro
    @State private var plan: BaselinePlan?
    @State private var position = 0
    @State private var results: [BaselineItemResult] = []
    @State private var showSkip = false
    @FocusState private var focus: IntroFocus?

    var body: some View {
        ZStack {
            switch stage {
            case .intro: intro
            case .playing: playing
            case .outro: outro
            }
            if showSkip {
                ConfirmOverlay(
                    title: "Skip the games?",
                    message: "That's okay. We can start from the very first sounds.",
                    keepTitle: "Keep playing",
                    leaveTitle: "Skip for now",
                    keepID: "baseline.menu.continue",
                    leaveID: "baseline.menu.skip",
                    onKeep: { showSkip = false },
                    onLeave: {
                        showSkip = false
                        finishBaseline()
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSkip)
        .animation(.easeInOut(duration: 0.25), value: stage)
    }

    // MARK: Intro

    private var intro: some View {
        VStack(spacing: 44) {
            Spacer()
            WrenSays(text: "Let's play a few sound games! There is no winning or losing. It is just for fun.", mood: .cheer, wrenSize: 190)
            HStack(spacing: 40) {
                StoryButton(prominent: true, action: { startPlaying() }) {
                    Label("Let's play", systemImage: "play.fill").font(Theme.headingFont)
                }
                .focused($focus, equals: .start)
                .accessibilityLabel("Let's play")
                .accessibilityHint("Starts a few short sound games.")
                .a11yID("baseline.start")

                StoryButton(action: { finishBaseline() }) {
                    Text("Skip for now").font(Theme.bodyFont)
                }
                .focused($focus, equals: .skip)
                .accessibilityLabel("Skip for now")
                .accessibilityHint("Starts from the very first sounds instead.")
                .a11yID("baseline.skip")
            }
            .focusSection()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .screenContainer()
        .defaultFocus($focus, IntroFocus.start)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focus = .start } }
        .onExitCommand { env.route = .home }
    }

    // MARK: Playing

    @ViewBuilder
    private var playing: some View {
        if let plan = plan, plan.activities.indices.contains(position) {
            let activity = plan.activities[position]
            ActivityContainerView(
                activity: activity,
                mode: .baseline,
                sessionId: plan.id,
                startsModelled: false,
                env: env,
                progressText: "Game \(position + 1)",
                nextLabel: "Next game",
                inputDisabled: showSkip,
                onFinish: { result in handle(result) },
                onMenu: { showSkip = true }
            )
            .id("baseline-\(position)")
        } else {
            Color.clear.screenContainer()
        }
    }

    // MARK: Outro

    private var outro: some View {
        VStack(spacing: 44) {
            Spacer()
            WrenSays(text: "All done! Thank you for playing. Now I know where to start our adventure.", mood: .cheer, wrenSize: 190)
            StoryButton(prominent: true, action: { env.route = .home }) {
                Label("Start my adventure", systemImage: "sparkles").font(Theme.headingFont)
            }
            .focused($focus, equals: .finish)
            .accessibilityLabel("Start my adventure")
            .a11yID("baseline.finish")
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .screenContainer()
        .defaultFocus($focus, IntroFocus.finish)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focus = .finish } }
        .onExitCommand { env.route = .home }
    }

    // MARK: Logic

    private func startPlaying() {
        let seed = SeededRNG.stableHash(env.snapshot.profile.id)
        let p = Baseline.plan(index: env.index, seed: seed)
        plan = p
        position = 0
        results = []
        if p.activities.isEmpty {
            finishBaseline()
        } else {
            stage = .playing
        }
    }

    private func handle(_ result: ActivityResult) {
        results.append(BaselineItemResult(activity: result.activity, answer: result.answer))
        guard let plan = plan else { finishBaseline(); return }
        if Baseline.shouldStop(results: results) || position + 1 >= plan.activities.count || position + 1 >= 10 {
            finishBaseline()
        } else {
            position += 1
        }
    }

    /// Scores what was played (nothing played = start at the first sound), records the placement, and shows the outro.
    private func finishBaseline() {
        env.cancelSequence()
        let placement = Baseline.score(index: env.index, results: results, now: env.now)
        env.update { snap in
            snap = Progression.applyPlacement(placement, to: snap)
        }
        env.awardSticker("welcome")
        env.flush()
        stage = .outro
    }
}
