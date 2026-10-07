import SwiftUI
import StorySoundsCore

/// One activity on screen: caption + hear-again controls, the activity-specific content, feedback, the
/// "let's do it together" panel and the Next button. Used by both sessions and the baseline.
/// Give it `.id(...)` per activity so each one gets a fresh coordinator and fresh focus.
@MainActor
struct ActivityContainerView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var coord: ActivityCoordinator
    @FocusState private var focus: ActivityFocus?
    @State private var lastFocus: ActivityFocus?

    let progressText: String
    let nextLabel: String
    /// True while a confirmation sits on top: everything underneath becomes non-focusable.
    let inputDisabled: Bool
    let onFinish: (ActivityResult) -> Void
    /// Menu / Back was pressed.
    let onMenu: () -> Void

    init(activity: Activity, mode: ActivityMode, sessionId: String, startsModelled: Bool, env: AppEnvironment,
         progressText: String, nextLabel: String = "Next", inputDisabled: Bool,
         onFinish: @escaping (ActivityResult) -> Void, onMenu: @escaping () -> Void) {
        _coord = StateObject(wrappedValue: ActivityCoordinator(activity: activity, mode: mode, sessionId: sessionId,
                                                               startsModelled: startsModelled, env: env))
        self.progressText = progressText
        self.nextLabel = nextLabel
        self.inputDisabled = inputDisabled
        self.onFinish = onFinish
        self.onMenu = onMenu
    }

    private var initialFocus: ActivityFocus {
        switch coord.activity.payload {
        case .choose, .picture, .tricky, .sentence: return .choice(0)
        case .blend: return .sound(0)
        case .order, .segment, .build: return .tile(0)
        case .story: return .pageNext
        case .fluency: return .word(0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                content
                    .frame(maxWidth: .infinity)
                    .disabled(!coord.contentEnabled)
                    .padding(.vertical, 12)
            }
            .scrollClipDisabled()
            .accessibilitySortPriority(2)
            footer
                .accessibilitySortPriority(1)
        }
        .screenContainer()
        .overlay(alignment: .top) { SoundCaptionPill().padding(.top, 20) }
        .defaultFocus($focus, initialFocus)
        .disabled(inputDisabled)
        .onAppear {
            coord.begin()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focus = initialFocus }
        }
        .onChange(of: focus) { _, new in
            if let f = new { lastFocus = f }
        }
        .onChange(of: inputDisabled) { _, disabled in
            // Restore focus to where it was before the confirmation opened.
            if !disabled {
                let target = lastFocus ?? initialFocus
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focus = target }
            }
        }
        .onChange(of: coord.phase) { _, newPhase in
            switch newPhase {
            case .modelled:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focus = .step }
            case .complete:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focus = .next }
            default:
                break
            }
        }
        .onExitCommand { onMenu() }
        .onPlayPauseCommand { coord.playPrompt(slow: false) }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 28) {
            WrenView(mood: coord.phase == .complete ? .cheer : .happy, size: 120)
            VStack(alignment: .leading, spacing: 8) {
                Text(progressText).font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
                    .a11yID("\(coord.idPrefix).progress")
                Text(coord.activity.prompt)
                    .font(Theme.headingFont)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .a11yID("\(coord.idPrefix).prompt")
            }
            .accessibilitySortPriority(4)
            Spacer(minLength: 20)
            HStack(spacing: 20) {
                StoryButton(action: { coord.playPrompt(slow: false) }) {
                    Label("Hear it again", systemImage: "speaker.wave.2.fill").font(Theme.captionFont)
                }
                .focused($focus, equals: .hear)
                .accessibilityLabel("Hear it again")
                .accessibilityHint("Plays the instruction again. You can also press Play Pause.")
                .a11yID("\(coord.idPrefix).hearAgain")

                StoryButton(action: { coord.playPrompt(slow: true) }) {
                    Label("Slowly", systemImage: "tortoise.fill").font(Theme.captionFont)
                }
                .focused($focus, equals: .slow)
                .accessibilityLabel("Hear it slowly")
                .a11yID("\(coord.idPrefix).hearSlow")
            }
            .focusSection()
            .accessibilityElement(children: .contain)
            .accessibilitySortPriority(3)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch coord.activity.payload {
        case let .choose(choices, target, _):
            ChooseActivityView(coord: coord, choices: choices, target: target, focus: $focus)
        case let .blend(graphemes, word, choices, _):
            BlendActivityView(coord: coord, graphemes: graphemes, word: word, choices: choices, focus: $focus)
        case let .order(graphemes, tiles, word, emoji):
            TileActivityView(coord: coord, kind: .order, graphemes: graphemes, tiles: tiles, word: word, emoji: emoji, focus: $focus)
        case let .segment(word, graphemes, tiles, emoji):
            TileActivityView(coord: coord, kind: .segment, graphemes: graphemes, tiles: tiles, word: word, emoji: emoji, focus: $focus)
        case let .build(word, graphemes, tiles, emoji):
            TileActivityView(coord: coord, kind: .build, graphemes: graphemes, tiles: tiles, word: word, emoji: emoji, focus: $focus)
        case let .picture(word, choices):
            PictureActivityView(coord: coord, word: word, choices: choices, focus: $focus)
        case let .tricky(word, choices):
            TrickyActivityView(coord: coord, word: word, choices: choices, focus: $focus)
        case let .sentence(tokens, blankIndex, choices, emoji):
            SentenceActivityView(coord: coord, tokens: tokens, blankIndex: blankIndex, choices: choices, emoji: emoji, focus: $focus)
        case let .story(title, pages, questions):
            StoryActivityView(coord: coord, title: title, pages: pages, questions: questions, focus: $focus)
        case let .fluency(words, _):
            FluencyActivityView(coord: coord, words: words, focus: $focus)
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 20) {
            if case let .modelled(step) = coord.phase {
                modelledPanel(step: step)
            }
            if let f = coord.feedback {
                FeedbackBannerView(text: f.text, positive: f.positive, identifier: "\(coord.idPrefix).feedback")
                    .transition(.opacity)
            }
            if coord.phase == .complete {
                HStack {
                    Spacer()
                    StoryButton(prominent: true, action: {
                        if let r = coord.result { onFinish(r) }
                    }) {
                        Label(nextLabel, systemImage: "chevron.right").font(Theme.bodyFont)
                    }
                    .focused($focus, equals: .next)
                    .accessibilityLabel(nextLabel)
                    .a11yID("\(coord.idPrefix).next")
                    Spacer()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: coord.phase)
    }

    private func modelledPanel(step: Int) -> some View {
        let text = coord.steps.indices.contains(step) ? coord.steps[step] : ""
        let last = step + 1 >= coord.steps.count
        return VStack(spacing: 20) {
            HStack(spacing: 24) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44)).foregroundStyle(Theme.accent).accessibilityHidden(true)
                Text(text).font(Theme.headingFont).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .a11yID("\(coord.idPrefix).model.text")
                Spacer(minLength: 0)
            }
            StoryButton(prominent: true, action: { coord.advanceModel() }) {
                Label(last ? "I'm ready" : "Next step", systemImage: "chevron.right").font(Theme.bodyFont)
            }
            .focused($focus, equals: .step)
            .accessibilityLabel(last ? "I'm ready" : "Next step")
            .a11yID("\(coord.idPrefix).model.next")
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.accent, lineWidth: 3))
        .accessibilityElement(children: .contain)
    }
}
