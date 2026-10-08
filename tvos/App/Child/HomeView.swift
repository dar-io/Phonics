import SwiftUI
import StorySoundsCore

/// Home: one obvious primary button, a few small secondary ones. Menu here uses the system behaviour
/// (leaves the app); there is no practice in progress at this point, so nothing can be lost.
@MainActor
struct HomeView: View {
    private enum Panel { case main, stickers }
    private enum Field: Hashable { case start, stickers, sound, gentle, grownups }

    @EnvironmentObject private var env: AppEnvironment
    @State private var panel: Panel = .main
    @FocusState private var focus: Field?
    /// Where focus lands when the main panel (re)appears: Start normally, the Sticker book button after closing it.
    @State private var landing: Field = .start

    private var baselineDone: Bool { env.snapshot.profile.baselineDone }

    var body: some View {
        ZStack {
            switch panel {
            case .main:
                mainPanel
            case .stickers:
                StickerBookView(onClose: closeStickers)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: panel)
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 36) {
                WrenView(mood: .happy, size: 220)
                Text("Hello, \(env.snapshot.profile.nickname)!")
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                    .a11yID("home.greeting")

                StoryButton(prominent: true, action: startAdventure) {
                    VStack(spacing: 8) {
                        Label("Today's adventure", systemImage: "book.fill")
                            .font(Font.system(size: 64, weight: .bold, design: .rounded))
                        Text(baselineDone ? "A short, friendly practice with Wren" : "First, a few sound games")
                            .font(Theme.captionFont)
                    }
                    .padding(.horizontal, 40).padding(.vertical, 16)
                }
                .focused($focus, equals: .start)
                .accessibilityLabel("Today's adventure")
                .accessibilityHint(baselineDone ? "Starts a short practice." : "Starts a few sound games to find the right place to begin.")
                .a11yID("home.start")
            }
            Spacer(minLength: 0)

            HStack(spacing: 28) {
                StoryButton(action: { openStickers() }) {
                    Label("Sticker book", systemImage: "star.square.fill").font(Theme.captionFont)
                }
                .focused($focus, equals: .stickers)
                .accessibilityLabel("Sticker book")
                .accessibilityValue("\(env.snapshot.profile.stickers.count) stickers")
                .a11yID("home.stickers")

                StoryButton(action: { env.setSoundOn(!env.soundOn) }) {
                    Label(env.soundOn ? "Sound: on" : "Sound: off",
                          systemImage: env.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(Theme.captionFont)
                }
                .focused($focus, equals: .sound)
                .accessibilityLabel("Sound")
                .accessibilityValue(env.soundOn ? "On" : "Off")
                .accessibilityHint("Turns sound on or off.")
                .a11yID("home.sound")

                StoryButton(action: { env.setGentleMode(!env.settings.gentleMode) }) {
                    Label(env.settings.gentleMode ? "Gentle mode: on" : "Gentle mode: off",
                          systemImage: env.settings.gentleMode ? "leaf.fill" : "leaf")
                        .font(Theme.captionFont)
                }
                .focused($focus, equals: .gentle)
                .accessibilityLabel("Gentle mode")
                .accessibilityValue(env.settings.gentleMode ? "On" : "Off")
                .accessibilityHint("Quieter sounds and no movement.")
                .a11yID("home.gentle")

                StoryButton(action: { env.route = .parent }) {
                    Label("Grown-ups", systemImage: "person.2.fill").font(Theme.captionFont)
                }
                .focused($focus, equals: .grownups)
                .accessibilityLabel("Grown-ups")
                .accessibilityHint("Opens the area for parents and carers.")
                .a11yID("home.grownups")
            }
            .focusSection()
            .accessibilityElement(children: .contain)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .screenContainer()
        .defaultFocus($focus, landing)
        .task {
            // ONE focus assignment per appearance; `landing` already holds the right target.
            try? await Task.sleep(nanoseconds: 100_000_000)
            focus = landing
            landing = .start
        }
    }

    private func startAdventure() {
        env.route = baselineDone ? .session : .baseline
    }

    private func openStickers() {
        panel = .stickers
    }

    /// Closing the sticker book returns focus to the control that opened it.
    private func closeStickers() {
        landing = .stickers
        panel = .main
    }
}
