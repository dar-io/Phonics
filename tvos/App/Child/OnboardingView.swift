import SwiftUI
import StorySoundsCore

/// First launch: pick a friendly nickname from a few presets. No real names, photos or birthdays are collected.
@MainActor
struct OnboardingView: View {
    private static let names: [String] = ["Reader", "Star", "Sunny", "Pip", "Fox", "Bear", "Moon", "Maple"]

    @EnvironmentObject private var env: AppEnvironment
    @FocusState private var focus: Int?

    var body: some View {
        VStack(spacing: 36) {
            Spacer(minLength: 0)
            WrenSays(text: "Hello! I'm Wren. Pick a friendly name for our adventures.", mood: .cheer, wrenSize: 170)
                .a11yID("onboarding.welcome")
            Text("Grown-ups: please choose a nickname, not a real name.")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 32), count: 4)
            LazyVGrid(columns: columns, spacing: 32) {
                ForEach(Array(Self.names.enumerated()), id: \.offset) { i, name in
                    StoryButton(prominent: i == 0, action: { choose(name) }) {
                        Text(name)
                            .font(Theme.headingFont)
                            .frame(maxWidth: .infinity, minHeight: 100)
                    }
                    .focused($focus, equals: i)
                    .accessibilityLabel(name)
                    .accessibilityHint("Chooses this nickname.")
                    .a11yID("onboarding.name.\(i)")
                }
            }
            .focusSection()
            .accessibilityElement(children: .contain)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .screenContainer()
        .defaultFocus($focus, 0)
        .task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            focus = 0
        }
    }

    private func choose(_ name: String) {
        env.update { $0.profile.nickname = name }
        env.flush()
        env.route = .baseline
    }
}
