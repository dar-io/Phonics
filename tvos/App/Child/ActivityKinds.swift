import SwiftUI
import UIKit
import StorySoundsCore

typealias ActivityFocusBinding = FocusState<ActivityFocus?>.Binding

private func afterTick(_ delay: Double = 0, _ block: @escaping () -> Void) {
    if delay <= 0 {
        DispatchQueue.main.async(execute: block)
    } else {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }
}

private func choiceFont(for label: String) -> Font {
    let n = label.count
    let size: CGFloat = n <= 2 ? 130 : (n <= 4 ? 100 : (n <= 6 ? 80 : 60))
    return Font.system(size: size, weight: .bold, design: .rounded)
}

// MARK: - Choice grid (used by choose, blend, picture, tricky, sentence and story questions)

@MainActor
struct ChoiceGridView: View {
    enum Style { case text, emoji }

    @ObservedObject var coord: ActivityCoordinator
    let choices: [Choice]
    let style: Style
    let gate: Bool
    let focus: ActivityFocusBinding

    init(coord: ActivityCoordinator, choices: [Choice], style: Style = .text, gate: Bool = true, focus: ActivityFocusBinding) {
        self.coord = coord
        self.choices = choices
        self.style = style
        self.gate = gate
        self.focus = focus
    }

    private var columnCount: Int { choices.count == 4 ? 2 : min(3, max(1, choices.count)) }

    var body: some View {
        // Spacing is kept modest so the 2x2 choose-sound screen fits at 1920x1080 beside the 100 pt caption slot.
        let columns = Array(repeating: GridItem(.flexible(), spacing: 28), count: columnCount)
        LazyVGrid(columns: columns, spacing: 28) {
            ForEach(Array(choices.enumerated()), id: \.offset) { i, c in
                card(i, c)
            }
        }
        .focusSection()
        .accessibilityElement(children: .contain)
        .onChange(of: coord.phase) { _, newPhase in
            if newPhase == .guided, let i = choices.firstIndex(where: { $0.correct }) {
                afterTick(0.05) { focus.wrappedValue = .choice(i) }
            }
        }
        .onChange(of: coord.wrongIds) { _, _ in
            // The card that was just tried is no longer focusable: move to the first one that still is.
            if coord.phase == .answering, let i = choices.indices.first(where: { coord.canSelect(choices[$0]) }) {
                afterTick(0.05) { focus.wrappedValue = .choice(i) }
            }
        }
    }

    @ViewBuilder
    private func card(_ i: Int, _ c: Choice) -> some View {
        let tried = coord.wasTried(c)
        let highlighted = coord.isHighlighted(c)
        StoryButton(prominent: highlighted, action: { coord.choose(c, in: choices) }) {
            VStack(spacing: 12) {
                if style == .emoji {
                    Text(c.emoji ?? "\u{2753}").font(.system(size: 120))
                } else {
                    Text(AccessibilityText.display(c.label))
                        .font(choiceFont(for: c.label))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                if tried {
                    Label("Tried", systemImage: "circle.dashed").font(Theme.captionFont)
                } else if highlighted {
                    Label("Try this one", systemImage: "star.fill").font(Theme.captionFont)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 170)
        }
        .disabled(!(gate && coord.canSelect(c)))
        .opacity(tried ? 0.45 : 1)
        .focused(focus, equals: .choice(i))
        .accessibilityLabel(choiceAccessibilityLabel(c, tried: tried))
        .accessibilityHint(highlighted ? "This answer is highlighted to help you." : "")
        .a11yID("\(coord.idPrefix).choice.\(i)")
    }

    private func choiceAccessibilityLabel(_ c: Choice, tried: Bool) -> String {
        let base = AccessibilityText.spoken(c.label)
        return tried ? "\(base), already tried" : base
    }
}

// MARK: - Choose (listen / find / match sound)

@MainActor
struct ChooseActivityView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var coord: ActivityCoordinator
    let choices: [Choice]
    let target: String
    let focus: ActivityFocusBinding

    var body: some View {
        VStack(spacing: 20) {
            if coord.activity.type == .matchSoundGrapheme {
                VStack(spacing: 8) {
                    Text("These letters").font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
                    Text(AccessibilityText.display(target)).font(Theme.glyphFont).foregroundStyle(Theme.accent)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("These letters: \(AccessibilityText.spoken(target))")
                .a11yID("\(coord.idPrefix).target")
            } else {
                VStack(spacing: 8) {
                    Label("The sound", systemImage: "speaker.wave.2.fill").font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
                    Text(env.phoneme(ofUnit: coord.activity.unitId)).font(Theme.glyphFont).foregroundStyle(Theme.accent)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("A sound to listen for. Press Play Pause to hear it again.")
                .a11yID("\(coord.idPrefix).target")
            }
            ChoiceGridView(coord: coord, choices: choices, style: .text, focus: focus)
        }
    }
}

// MARK: - Blend

@MainActor
struct BlendActivityView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var coord: ActivityCoordinator
    let graphemes: [String]
    let word: String
    let choices: [Choice]
    let focus: ActivityFocusBinding
    @State private var lit: Set<Int> = []

    private var allLit: Bool { coord.phase != .answering || lit.count >= graphemes.count }

    var body: some View {
        VStack(spacing: 32) {
            HStack(spacing: 24) {
                ForEach(Array(graphemes.enumerated()), id: \.offset) { i, g in
                    soundTile(i, g)
                }
            }
            .focusSection()
            .accessibilityElement(children: .contain)

            if !allLit {
                Label("Press Select on each sound, one by one.", systemImage: "hand.point.up.left.fill")
                    .font(Theme.bodyFont).foregroundStyle(Theme.textSecondary)
            } else if coord.isComplete {
                Text(word).font(Theme.wordFont).foregroundStyle(Theme.positive)
                    .a11yID("\(coord.idPrefix).word")
            } else {
                Label("Now blend them. Which word is it?", systemImage: "arrow.down.circle.fill")
                    .font(Theme.bodyFont).foregroundStyle(Theme.textSecondary)
            }

            ChoiceGridView(coord: coord, choices: choices, style: .text, gate: allLit, focus: focus)
        }
    }

    @ViewBuilder
    private func soundTile(_ i: Int, _ g: String) -> some View {
        let isLit = lit.contains(i) || coord.phase != .answering
        VStack(spacing: 10) {
            StoryButton(prominent: isLit, action: { lightUp(i) }) {
                Text(AccessibilityText.display(g))
                    .font(Font.system(size: 110, weight: .bold, design: .rounded))
                    .frame(minWidth: 120)
            }
            .disabled(!coord.contentEnabled)
            .focused(focus, equals: .sound(i))
            .accessibilityLabel("Sound \(i + 1), letters \(g.filter { $0 != "_" }.map { String($0).uppercased() }.joined(separator: " "))")
            .accessibilityValue(isLit ? "played" : "not played")
            .accessibilityHint("Plays this sound and lights it up.")
            .a11yID("\(coord.idPrefix).sound.\(i)")
            Image(systemName: isLit ? "checkmark.circle.fill" : "speaker.wave.2")
                .font(.system(size: 36))
                .foregroundStyle(isLit ? Theme.positive : Theme.textSecondary)
                .accessibilityHidden(true)
        }
    }

    private func lightUp(_ i: Int) {
        guard coord.contentEnabled else { return }
        if let audioId = GraphemeAudio.audioId(index: env.index, grapheme: graphemes[i], inWord: word) {
            env.playAudioInterrupting(audioId)
        }
        lit.insert(i)
        if lit.count >= graphemes.count {
            let target = choices.indices.first(where: { coord.canSelect(choices[$0]) }) ?? 0
            afterTick(0.1) { focus.wrappedValue = .choice(target) }
        } else if env.settings.gentleMode || UIAccessibility.isVoiceOverRunning {
            return   // no unprompted focus movement for Gentle mode or VoiceOver users
        } else if let next = graphemes.indices.first(where: { $0 > i && !lit.contains($0) }) ?? graphemes.indices.first(where: { !lit.contains($0) }) {
            afterTick { focus.wrappedValue = .sound(next) }
        }
    }
}

// MARK: - Order / segment / build (tile selection, never dragging)

@MainActor
struct TileActivityView: View {
    enum Kind { case order, segment, build }

    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var coord: ActivityCoordinator
    let kind: Kind
    let graphemes: [String]
    let tiles: [String]
    let word: String
    let emoji: String?
    let focus: ActivityFocusBinding
    @State private var placed: [Int] = []

    private var guidedTarget: Int? {
        guard coord.isGuided, placed.count < graphemes.count else { return nil }
        let expected = graphemes[placed.count]
        return tiles.indices.first(where: { !placed.contains($0) && tiles[$0] == expected })
    }

    private func canTap(_ i: Int) -> Bool {
        guard coord.contentEnabled, !placed.contains(i) else { return false }
        if coord.isGuided { return i == guidedTarget }
        return true
    }

    private var instruction: String {
        switch kind {
        case .order: return "Choose the sounds in order."
        case .segment: return "Choose each sound of the word, in order."
        case .build: return "Choose the letters to build the word."
        }
    }

    var body: some View {
        VStack(spacing: 30) {
            HStack(spacing: 28) {
                if let e = emoji, !e.isEmpty { Text(e).font(.system(size: 100)).accessibilityHidden(true) }
                Text(word).font(Theme.wordFont).foregroundStyle(Theme.accent)
                    .accessibilityLabel("The word is \(word)")
                    .a11yID("\(coord.idPrefix).word")
            }
            Text(instruction).font(Theme.captionFont).foregroundStyle(Theme.textSecondary)

            // Slots (display only)
            HStack(spacing: 20) {
                ForEach(0..<graphemes.count, id: \.self) { k in
                    slot(k)
                }
            }
            .accessibilityElement(children: .contain)

            // Tiles
            HStack(spacing: 24) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { i, g in
                    tileButton(i, g)
                }
            }
            .focusSection()
            .accessibilityElement(children: .contain)

            StoryButton(action: { backOne() }) {
                Label("Back one", systemImage: "arrow.uturn.backward").font(Theme.bodyFont)
            }
            .disabled(placed.isEmpty || !coord.contentEnabled || coord.isGuided)
            .focused(focus, equals: .back)
            .accessibilityLabel("Back one")
            .accessibilityHint("Takes the last chosen sound out of the word.")
            .a11yID("\(coord.idPrefix).back")
        }
        .onChange(of: coord.phase) { _, newPhase in
            if newPhase == .guided { refocus() }
        }
    }

    @ViewBuilder
    private func slot(_ k: Int) -> some View {
        let filled = k < placed.count
        let text = filled ? AccessibilityText.display(tiles[placed[k]]) : ""
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(filled ? Theme.surfaceRaised : Theme.surface)
            RoundedRectangle(cornerRadius: 20)
                .stroke(filled ? Theme.positive : Theme.textSecondary, style: StrokeStyle(lineWidth: 4, dash: filled ? [] : [12, 8]))
            Text(filled ? text : "\(k + 1)")
                .font(Font.system(size: filled ? 80 : 44, weight: .bold, design: .rounded))
                .foregroundStyle(filled ? Theme.text : Theme.textSecondary)
        }
        .frame(width: 150, height: 140)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(filled ? "Place \(k + 1): \(AccessibilityText.spoken(tiles[placed[k]]))" : "Place \(k + 1): empty")
        .a11yID("\(coord.idPrefix).slot.\(k)")
    }

    @ViewBuilder
    private func tileButton(_ i: Int, _ g: String) -> some View {
        let used = placed.contains(i)
        let isGuide = guidedTarget == i
        VStack(spacing: 8) {
            StoryButton(prominent: isGuide, action: { tap(i) }) {
                Text(AccessibilityText.display(g))
                    .font(Font.system(size: 90, weight: .bold, design: .rounded))
                    .frame(minWidth: 110)
            }
            .disabled(!canTap(i))
            .opacity(used ? 0.25 : 1)
            .focused(focus, equals: .tile(i))
            .accessibilityLabel(used ? "\(AccessibilityText.spoken(g)), already used" : AccessibilityText.spoken(g))
            .a11yID("\(coord.idPrefix).tile.\(i)")
            if isGuide {
                Label("Next", systemImage: "star.fill").font(Theme.captionFont)
            } else if used {
                Image(systemName: "checkmark").font(.system(size: 30)).accessibilityHidden(true)
            }
        }
    }

    private func tap(_ i: Int) {
        guard canTap(i) else { return }
        if let audioId = GraphemeAudio.audioId(index: env.index, grapheme: tiles[i], inWord: word) {
            env.playAudioInterrupting(audioId)
        }
        placed.append(i)
        if placed.count == graphemes.count {
            evaluate()
        } else {
            refocus()
        }
    }

    private func evaluate() {
        let attempt = placed.map { tiles[$0] }
        if attempt == graphemes {
            coord.submit(correct: true, chosen: attempt.joined(separator: " "), expected: graphemes.joined(separator: " "))
        } else {
            let m = graphemes.indices.first(where: { attempt[$0] != graphemes[$0] }) ?? 0
            placed = []
            coord.submit(correct: false, chosen: attempt[m], expected: graphemes[m])
            refocus()
        }
    }

    private func backOne() {
        guard !placed.isEmpty, coord.contentEnabled, !coord.isGuided else { return }
        let removed = placed.removeLast()
        afterTick { focus.wrappedValue = .tile(removed) }
    }

    private func refocus() {
        afterTick(0.05) {
            if let g = guidedTarget {
                focus.wrappedValue = .tile(g)
            } else if let first = tiles.indices.first(where: { !placed.contains($0) }) {
                focus.wrappedValue = .tile(first)
            } else {
                focus.wrappedValue = .back
            }
        }
    }
}

// MARK: - Picture, tricky

@MainActor
struct PictureActivityView: View {
    @ObservedObject var coord: ActivityCoordinator
    let word: String
    let choices: [Choice]
    let focus: ActivityFocusBinding

    var body: some View {
        VStack(spacing: 36) {
            Text(word).font(Theme.wordFont).foregroundStyle(Theme.accent)
                .accessibilityLabel("The word is \(word)")
                .a11yID("\(coord.idPrefix).word")
            ChoiceGridView(coord: coord, choices: choices, style: .emoji, focus: focus)
        }
    }
}

@MainActor
struct TrickyActivityView: View {
    @ObservedObject var coord: ActivityCoordinator
    let word: String
    let choices: [Choice]
    let focus: ActivityFocusBinding

    var body: some View {
        VStack(spacing: 36) {
            VStack(spacing: 10) {
                Label("Tricky word", systemImage: "star.fill").font(Theme.captionFont).foregroundStyle(Theme.accent)
                Text(word).font(Theme.wordFont).foregroundStyle(Theme.text)
                    .underline(true, color: Theme.accent)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tricky word: \(word)")
            .a11yID("\(coord.idPrefix).word")
            ChoiceGridView(coord: coord, choices: choices, style: .text, focus: focus)
        }
    }
}

// MARK: - Sentence

@MainActor
struct SentenceActivityView: View {
    @ObservedObject var coord: ActivityCoordinator
    let tokens: [String]
    let blankIndex: Int
    let choices: [Choice]
    let emoji: String?
    let focus: ActivityFocusBinding

    private var answer: String? { choices.first(where: { $0.correct })?.label }

    private func sentenceText() -> Text {
        var t = Text("")
        for (i, tok) in tokens.enumerated() {
            if i == blankIndex {
                if coord.isComplete, let a = answer {
                    t = t + Text(a + " ").foregroundColor(Theme.positive).bold()
                } else {
                    t = t + Text("_____ ").foregroundColor(Theme.accent).underline()
                }
            } else {
                t = t + Text(tok + " ")
            }
        }
        return t.font(Font.system(size: 72, weight: .bold, design: .rounded))
    }

    /// Reads "blank" only while the blank is open; once answered the real word is read.
    private var sentenceAccessibilityLabel: String {
        let filled: String = (coord.isComplete ? answer : nil) ?? "blank"
        return tokens.enumerated().map { $0.offset == blankIndex ? filled : $0.element }.joined(separator: " ")
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 28) {
                if let e = emoji, !e.isEmpty { Text(e).font(.system(size: 100)).accessibilityHidden(true) }
                sentenceText()
                    .lineSpacing(12)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(sentenceAccessibilityLabel)
                    .a11yID("\(coord.idPrefix).sentence")
            }
            ChoiceGridView(coord: coord, choices: choices, style: .text, focus: focus)
        }
    }
}

// MARK: - Story

@MainActor
struct StoryActivityView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var coord: ActivityCoordinator
    let title: String
    let pages: [StoryPageContent]
    let questions: [StoryQuestion]
    let focus: ActivityFocusBinding
    @State private var page = 0
    @State private var asking = false

    private func pageText(_ p: StoryPageContent) -> Text {
        var t = Text("")
        for tok in p.tokens {
            if tok.tricky {
                t = t + Text(tok.text + " ").foregroundColor(Theme.accent).underline()
            } else {
                t = t + Text(tok.text + " ")
            }
        }
        return t.font(Font.system(size: 64, weight: .semibold, design: .rounded))
    }

    var body: some View {
        if asking, let q = questions.first {
            VStack(spacing: 32) {
                Text(q.prompt).font(Theme.headingFont).multilineTextAlignment(.center)
                    .a11yID("\(coord.idPrefix).question")
                ChoiceGridView(coord: coord, choices: q.choices, style: .text, focus: focus)
            }
        } else {
            readingPage
        }
    }

    private var readingPage: some View {
        let hasTricky = pages.indices.contains(page) && pages[page].tokens.contains(where: { $0.tricky })
        return VStack(spacing: 28) {
            if pages.indices.contains(page) {
                let p = pages[page]
                HStack(spacing: 36) {
                    if let e = p.emoji, !e.isEmpty { Text(e).font(.system(size: 150)).accessibilityHidden(true) }
                    pageText(p)
                        .lineSpacing(16)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(p.tokens.map { $0.tricky ? "\($0.text), tricky word" : $0.text }.joined(separator: " "))
                        .a11yID("\(coord.idPrefix).pageText")
                }
                .padding(32)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.surface))
            }
            if hasTricky {
                Label("Underlined words are tricky words.", systemImage: "star.fill")
                    .font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 40) {
                StoryButton(action: { previous() }) {
                    Label("Back a page", systemImage: "chevron.left").font(Theme.bodyFont)
                }
                .disabled(page == 0 || !coord.contentEnabled)
                .focused(focus, equals: .pagePrev)
                .accessibilityLabel("Back a page")
                .a11yID("\(coord.idPrefix).page.prev")

                Text("Page \(page + 1) of \(pages.count)").font(Theme.captionFont).foregroundStyle(Theme.textSecondary)

                StoryButton(prominent: true, action: { next() }) {
                    Label(isLastPage ? "Finish story" : "Next page", systemImage: "chevron.right").font(Theme.bodyFont)
                }
                .disabled(!coord.contentEnabled)
                .focused(focus, equals: .pageNext)
                .accessibilityLabel(isLastPage ? "Finish story" : "Next page")
                .a11yID("\(coord.idPrefix).page.next")
            }
            .focusSection()
        }
        .onChange(of: coord.phase) { _, newPhase in
            if newPhase == .guided { afterTick(0.05) { focus.wrappedValue = .pageNext } }
        }
    }

    private var isLastPage: Bool { page + 1 >= pages.count }

    private func previous() {
        guard page > 0 else { return }
        page -= 1
        env.playAudio("sfx-page-turn")
        if page == 0 {
            // "Back a page" is disabled on the first page: hand focus to "Next page" so it is never lost.
            afterTick { focus.wrappedValue = .pageNext }
        }
    }

    private func next() {
        guard coord.contentEnabled else { return }
        if !isLastPage {
            page += 1
            env.playAudio("sfx-page-turn")
        } else if !questions.isEmpty {
            asking = true
            afterTick(0.1) { focus.wrappedValue = .choice(0) }
        } else {
            coord.submitSelfReport(text: "You read the whole story! Lovely reading.")
        }
    }
}

// MARK: - Fluency (no timer, no ranking)

@MainActor
struct FluencyActivityView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var coord: ActivityCoordinator
    let words: [String]
    let focus: ActivityFocusBinding
    @State private var heard: Set<Int> = []

    var body: some View {
        VStack(spacing: 24) {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 28), count: 3)
            LazyVGrid(columns: columns, spacing: 28) {
                ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                    StoryButton(prominent: heard.contains(i), action: { tapWord(i, w) }) {
                        HStack(spacing: 14) {
                            Text(w).font(Font.system(size: w.count > 8 ? 64 : 80, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center).lineLimit(2)
                            if heard.contains(i) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).accessibilityHidden(true)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 130)
                    }
                    .disabled(!coord.contentEnabled)
                    .focused(focus, equals: .word(i))
                    .accessibilityLabel(heard.contains(i) ? "\(w), read" : w)
                    .accessibilityHint("Plays the word.")
                    .a11yID("\(coord.idPrefix).word.\(i)")
                }
            }
            .focusSection()
            .accessibilityElement(children: .contain)

            StoryButton(prominent: true, action: {
                coord.submitSelfReport(text: "Well done! You read those words.")
            }) {
                Label("I read them", systemImage: "checkmark").font(Theme.bodyFont)
            }
            .disabled(!coord.contentEnabled)
            .focused(focus, equals: .done)
            .accessibilityLabel("I read them")
            .a11yID("\(coord.idPrefix).done")
        }
        .onChange(of: coord.phase) { _, newPhase in
            if newPhase == .guided { afterTick(0.05) { focus.wrappedValue = .word(0) } }
        }
    }

    private func tapWord(_ i: Int, _ w: String) {
        env.playAudioInterrupting("w-" + w.lowercased())
        heard.insert(i)
    }
}
