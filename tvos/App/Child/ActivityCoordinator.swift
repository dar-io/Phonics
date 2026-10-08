import Foundation
import SwiftUI
import StorySoundsCore

enum ActivityMode: Equatable { case session, baseline }

enum ActivityPhase: Equatable {
    /// The child is answering.
    case answering
    /// "Let's sound it out together": narration steps are shown one at a time (controls are paused).
    case modelled(step: Int)
    /// Steps are done; the child completes the activity with the right answer highlighted.
    case guided
    /// Feedback is showing; the Next button is waiting.
    case complete
}

struct FeedbackLine: Equatable {
    let text: String
    let positive: Bool
}

struct ActivityResult {
    let activity: Activity
    /// Correct on the very first independent try.
    let firstTryCorrect: Bool
    /// Support level of the answer that finished the activity.
    let support: SupportLevel
    let answer: Answer
    /// The plan asked for this one to be done together from the start.
    let startedModelled: Bool
    /// At least one independent answer was not right before the activity finished.
    let hadMiss: Bool
}

/// Focus targets inside an activity screen.
enum ActivityFocus: Hashable {
    case hear, slow
    case choice(Int)
    case sound(Int)
    case tile(Int)
    case back
    case word(Int)
    case done
    case pagePrev, pageNext
    case step
    case next
}

/// Decides what every answer means: judges, records attempts, handles "wrong twice -> do it together",
/// and produces the feedback line. Activity views only report what the child chose.
@MainActor
final class ActivityCoordinator: ObservableObject {
    let activity: Activity
    let mode: ActivityMode
    let sessionId: String
    let startsModelled: Bool
    let steps: [String]

    @Published private(set) var phase: ActivityPhase = .answering
    @Published private(set) var feedback: FeedbackLine?
    @Published private(set) var missCount = 0
    @Published private(set) var wrongIds: Set<String> = []
    private(set) var result: ActivityResult?

    private let env: AppEnvironment
    private var shownAt = Date()
    private var started = false
    /// Names this activity's prompt sequence so leaving the screen cannot cut off the next activity's prompt.
    private var promptToken: Int?

    var idPrefix: String { mode == .baseline ? "baseline" : "session" }

    init(activity: Activity, mode: ActivityMode, sessionId: String, startsModelled: Bool, env: AppEnvironment) {
        self.activity = activity
        self.mode = mode
        self.sessionId = sessionId
        self.startsModelled = startsModelled && mode == .session
        self.env = env
        self.steps = ActivityGenerator.modelledSteps(activity)
    }

    // MARK: Lifecycle

    func begin() {
        if started { return }
        started = true
        shownAt = Date()
        if startsModelled { phase = .modelled(step: 0) }
        playPrompt(slow: false)
    }

    func playPrompt(slow: Bool) {
        promptToken = env.playSequence(activity.audioIds, slow: slow)
    }

    /// The screen is going away (next activity, summary, home): stop this activity's speech and sounds.
    func end() {
        if let token = promptToken { env.cancelSequence(token: token) }
        promptToken = nil
    }

    // MARK: Derived state

    var contentEnabled: Bool { phase == .answering || phase == .guided }
    var isGuided: Bool { phase == .guided }
    var isComplete: Bool { phase == .complete }

    func canSelect(_ choice: Choice) -> Bool {
        switch phase {
        case .answering: return !wrongIds.contains(choice.id)
        case .guided: return choice.correct
        case .modelled, .complete: return false
        }
    }

    func wasTried(_ choice: Choice) -> Bool { phase == .answering && wrongIds.contains(choice.id) }
    func isHighlighted(_ choice: Choice) -> Bool { phase == .guided && choice.correct }

    // MARK: Modelled path

    func advanceModel() {
        guard case let .modelled(step) = phase else { return }
        if step + 1 < steps.count {
            phase = .modelled(step: step + 1)
        } else {
            phase = .guided
        }
    }

    // MARK: Answers

    /// A choice card was selected.
    func choose(_ choice: Choice, in choices: [Choice]) {
        guard canSelect(choice) else { return }
        env.interruptPrompt()
        if let audio = choice.audioId { env.playAudio(audio) }
        let expected = choices.first(where: { $0.correct })?.label
        submit(correct: choice.correct, chosen: choice.label, expected: expected, choiceId: choice.id)
    }

    /// A judged answer (choice or finished tile sequence).
    func submit(correct: Bool, chosen: String?, expected: String?, choiceId: String? = nil) {
        if phase == .complete { return }
        let ms = Int(Date().timeIntervalSince(shownAt) * 1000)

        if mode == .baseline {
            let answer = Answer(correct: correct, support: .independent, responseMs: ms, chosen: chosen, expected: expected)
            finish(answer: answer, firstTry: correct, text: "Thank you! Let's try the next one.", positive: true, sfx: "sfx-tap")
            return
        }

        switch phase {
        case .modelled, .complete:
            return
        case .guided:
            if correct {
                let answer = Answer(correct: true, support: .modelled, responseMs: ms, chosen: chosen, expected: expected)
                record(answer)
                finish(answer: answer, firstTry: false, text: Feedback.text(for: activity, answer: answer), positive: true, sfx: "sfx-star")
            } else {
                feedback = FeedbackLine(text: "Let's follow the star together.", positive: false)
            }
        case .answering:
            let support: SupportLevel = missCount == 0 ? .independent : .prompted
            let answer = Answer(correct: correct, support: support, responseMs: ms, chosen: chosen, expected: expected)
            record(answer)
            if correct {
                finish(answer: answer, firstTry: missCount == 0, text: Feedback.text(for: activity, answer: answer), positive: true, sfx: "sfx-correct")
            } else {
                missCount += 1
                if let id = choiceId { wrongIds.insert(id) }
                env.playAudio("sfx-gentle-retry")
                if missCount >= 2 {
                    feedback = FeedbackLine(text: Feedback.text(for: activity, answer: answer), positive: false)
                    wrongIds = []
                    phase = .modelled(step: 0)
                } else {
                    feedback = FeedbackLine(text: "Good try! Have another look.", positive: false)
                }
            }
        }
    }

    /// For activities that are not right/wrong (reading a story, reading a word list). Recorded as prompted (or
    /// modelled) support because a self-report is not evidence of independent mastery.
    func submitSelfReport(text: String) {
        if phase == .complete { return }
        env.interruptPrompt()
        let ms = Int(Date().timeIntervalSince(shownAt) * 1000)
        let support: SupportLevel = (phase == .guided || startsModelled) ? .modelled : .prompted
        let answer = Answer(correct: true, support: support, responseMs: ms, chosen: nil, expected: nil)
        if mode == .session { record(answer) }
        finish(answer: answer, firstTry: false, text: text, positive: true, sfx: "sfx-star")
    }

    // MARK: Internals

    private func record(_ answer: Answer) {
        let attempt = Attempt(at: env.now, sessionId: sessionId, unitId: activity.unitId, track: activity.track,
                              activityType: activity.type, itemKey: activity.key, correct: answer.correct,
                              support: answer.support, responseMs: answer.responseMs, chosen: answer.chosen,
                              expected: answer.expected)
        env.recordAttempt(attempt)
    }

    private func finish(answer: Answer, firstTry: Bool, text: String, positive: Bool, sfx: String) {
        result = ActivityResult(activity: activity, firstTryCorrect: firstTry, support: answer.support,
                                answer: answer, startedModelled: startsModelled, hadMiss: missCount > 0)
        feedback = FeedbackLine(text: text, positive: positive)
        phase = .complete
        env.playAudio(sfx)
    }
}
