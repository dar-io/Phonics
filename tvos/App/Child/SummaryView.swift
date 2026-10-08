import SwiftUI
import StorySoundsCore

/// Calm end-of-session screen. Celebrates effort; no scores, no comparison, no streaks.
@MainActor
struct SummaryView: View {
    @EnvironmentObject private var env: AppEnvironment
    let summary: SessionSummary
    @FocusState private var doneFocused: Bool

    private var stickers: [StickerInfo] {
        summary.stickersEarned.map { StickerCatalog.info(for: $0, index: env.index) }
    }

    var body: some View {
        VStack(spacing: 36) {
            Spacer(minLength: 0)
            Text("Lovely work, \(env.snapshot.profile.nickname)!")
                .font(Theme.titleFont)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .a11yID("summary.title")
            WrenSays(text: Feedback.sessionEnd(activitiesDone: summary.activitiesDone), mood: .cheer, wrenSize: 170)
                .a11yID("summary.message")

            if !stickers.isEmpty {
                VStack(spacing: 16) {
                    Text(stickers.count == 1 ? "You earned a sticker!" : "You earned \(stickers.count) stickers!")
                        .font(Theme.headingFont).foregroundStyle(Theme.accent)
                    HStack(spacing: 36) {
                        ForEach(Array(stickers.enumerated()), id: \.offset) { _, s in
                            VStack(spacing: 8) {
                                Text(s.emoji).font(.system(size: 96)).accessibilityHidden(true)
                                Text(s.title).font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Sticker: \(s.title)")
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .a11yID("summary.stickers")
            }

            StoryButton(prominent: true, action: { env.route = .home }) {
                Label("Done", systemImage: "checkmark").font(Theme.headingFont)
            }
            .focused($doneFocused)
            .accessibilityLabel("Done")
            .accessibilityHint("Goes back to the home screen.")
            .a11yID("summary.done")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .screenContainer()
        .defaultFocus($doneFocused, true)
        .task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            doneFocused = true
        }
        .onExitCommand { env.route = .home }
    }
}
