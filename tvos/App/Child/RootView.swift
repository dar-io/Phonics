import SwiftUI
import StorySoundsCore

/// Owns the current `AppEnvironment` so a failed load can be retried without relaunching the app.
@MainActor
final class EnvironmentHost: ObservableObject {
    @Published private(set) var env: AppEnvironment
    private let arguments: [String]

    init(arguments: [String] = CommandLine.arguments) {
        self.arguments = arguments
        self.env = AppEnvironment.make(arguments: arguments)
    }

    /// Grown-up chose "Start fresh" on the unreadable-progress screen: open a NEW profile and leave the unreadable data
    /// on disk, untouched. Test-only reset / forced-error flags are dropped so nothing is wiped.
    func startFresh() {
        let cleaned = arguments.filter { $0 != "-uitest-reset" && $0 != "-uitest-force-load-error" }
        env = AppEnvironment.make(arguments: cleaned, startFresh: true)
    }

    func retry() {
        // A retry must not wipe data again, so test-only reset flags are dropped.
        // The forced-error test flag is dropped too, so Retry can actually succeed in UI tests.
        let cleaned = arguments.filter { $0 != "-uitest-reset" && $0 != "-uitest-force-load-error" }
        env = AppEnvironment.make(arguments: cleaned)
    }
}

@MainActor
struct RootView: View {
    @ObservedObject var host: EnvironmentHost
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let message = host.env.loadFailure {
                // Self-contained: `StoryButton` reads `AppEnvironment` from the environment, and this branch sits
                // outside `RouterView`, so the object must be supplied here or the screen would crash on appear.
                LoadErrorView(message: message, canStartFresh: host.env.progressUnreadable,
                              onRetry: { host.retry() }, onStartFresh: { host.startFresh() })
                    .environmentObject(host.env)
            } else {
                RouterView().environmentObject(host.env)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                break
            case .inactive:
                // Siri, system alerts and HDMI-CEC make the scene inactive without leaving: only save.
                host.env.flush()
            case .background:
                host.env.sceneLeftForeground()
            @unknown default:
                host.env.sceneLeftForeground()
            }
        }
    }
}

@MainActor
struct RouterView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        ZStack {
            switch env.route {
            case .onboarding:
                OnboardingView().transition(.opacity)
            case .home:
                HomeView().transition(.opacity)
            case .baseline:
                BaselineView().transition(.opacity)
            case .session:
                SessionRunnerView().transition(.opacity)
            case let .summary(summary):
                SummaryView(summary: summary).transition(.opacity)
            case .parent:
                // ParentAreaView is owned by the parent UI. It leaves by setting `env.route = .home`.
                ParentAreaView()
                    .environment(\.parentBackup, env.parentBackup)
                    .onExitCommand { env.route = .home }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: env.route)
        .background(Theme.background.ignoresSafeArea())
    }
}

/// Friendly, non-technical screen shown if the bundled lessons cannot be opened, or saved progress cannot be read.
/// Never crashes. For unreadable progress a second, deliberately quiet option starts a NEW profile behind a two-step
/// confirm (Cancel is focused first); the unreadable data is kept aside, never deleted.
@MainActor
struct LoadErrorView: View {
    let message: String
    var canStartFresh: Bool = false
    let onRetry: () -> Void
    var onStartFresh: () -> Void = {}
    @State private var confirming = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case retry, startFresh, confirm, cancel }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            WrenSays(text: message, mood: .think, wrenSize: 190)
                .a11yID("loaderror.message")
            if confirming {
                confirmPanel
            } else {
                mainPanel
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .screenContainer()
        .defaultFocus($focus, confirming ? Field.cancel : Field.retry)
        .onExitCommand {
            // Menu inside the confirm step means "never mind". On the main panel it still leaves the app.
            if confirming { cancelConfirm() }
        }
        .task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            focus = .retry
        }
    }

    private var mainPanel: some View {
        VStack(spacing: 28) {
            StoryButton(prominent: true, action: onRetry) {
                Label("Try again", systemImage: "arrow.clockwise").font(Theme.headingFont)
            }
            .focused($focus, equals: .retry)
            .accessibilityLabel("Try again")
            .a11yID("loaderror.retry")
            if canStartFresh {
                StoryButton(action: { enterConfirm() }) {
                    Text("Start fresh (keeps the unreadable data aside)")
                        .font(Theme.bodyFont)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .focused($focus, equals: .startFresh)
                .accessibilityLabel("Start fresh. Keeps the unreadable data aside.")
                .accessibilityHint("A grown-up should choose this. Asks you to confirm first.")
                .a11yID("loaderror.startfresh")
            }
            Text("If this keeps happening, please ask a grown-up to restart the app.")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var confirmPanel: some View {
        VStack(spacing: 28) {
            Text("For a grown-up: start a new adventure? The old saved data stays on this Apple TV, set aside and not deleted. Only the new adventure will be used from now on.")
                .font(Theme.bodyFont)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .a11yID("loaderror.confirmtext")
            HStack(spacing: 40) {
                StoryButton(prominent: true, action: { cancelConfirm() }) {
                    Text("Cancel").font(Theme.headingFont)
                }
                .focused($focus, equals: .cancel)
                .a11yID("loaderror.cancel")
                StoryButton(action: onStartFresh) {
                    Text("Yes, start fresh").font(Theme.headingFont)
                }
                .focused($focus, equals: .confirm)
                .a11yID("loaderror.confirm")
            }
        }
    }

    private func enterConfirm() {
        confirming = true
        focus = .cancel
        // The buttons are rebuilt by the state change: set focus again on the next turn.
        DispatchQueue.main.async { focus = .cancel }
    }

    private func cancelConfirm() {
        confirming = false
        focus = .startFresh
        DispatchQueue.main.async { focus = .startFresh }
    }
}
