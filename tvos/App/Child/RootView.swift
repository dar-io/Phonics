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
                LoadErrorView(message: message, onRetry: { host.retry() })
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

/// Friendly, non-technical screen shown if the bundled lessons cannot be opened. Never crashes.
@MainActor
struct LoadErrorView: View {
    let message: String
    let onRetry: () -> Void
    @FocusState private var retryFocused: Bool

    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            WrenSays(text: message, mood: .think, wrenSize: 190)
                .a11yID("loaderror.message")
            StoryButton(prominent: true, action: onRetry) {
                Label("Try again", systemImage: "arrow.clockwise").font(Theme.headingFont)
            }
            .focused($retryFocused)
            .accessibilityLabel("Try again")
            .a11yID("loaderror.retry")
            Text("If this keeps happening, please ask a grown-up to restart the app.")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .screenContainer()
        .defaultFocus($retryFocused, true)
        .task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            retryFocused = true
        }
    }
}
