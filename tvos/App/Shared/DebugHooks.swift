import Foundation
import StorySoundsCore

/// UI-test-only activity arrangement. The whole body is compiled out of Release builds, so a shipping app can
/// never reorder (or reveal) the correct answer.
enum DebugHooks {
    /// With `-uitest-first-choice-wrong`: puts the correct choice LAST and fills the earlier slots with wrong ones
    /// (padding with synthetic wrong choices so there are at least three), so pressing Select on whatever is
    /// focused misses twice in a row and the "do it together" path is reached deterministically.
    static func arranged(_ activity: Activity, options: LaunchOptions) -> Activity {
        #if DEBUG
        guard options.firstChoiceWrong else { return activity }
        func reorder(_ choices: [Choice]) -> [Choice] {
            guard let right = choices.first(where: { $0.correct }) else { return choices }
            var wrong = choices.filter { !$0.correct }
            var n = 0
            while wrong.count < 3 {
                n += 1
                wrong.append(Choice(id: "uitest-wrong-\(n)", label: "zz\(n)", audioId: nil, emoji: "\u{2753}", correct: false))
            }
            return wrong + [right]
        }
        let payload: ActivityPayload
        switch activity.payload {
        case let .choose(choices, target, emoji):
            payload = .choose(choices: reorder(choices), target: target, emoji: emoji)
        case let .blend(graphemes, word, choices, emoji):
            payload = .blend(graphemes: graphemes, word: word, choices: reorder(choices), emoji: emoji)
        case let .picture(word, choices):
            payload = .picture(word: word, choices: reorder(choices))
        case let .tricky(word, choices):
            payload = .tricky(word: word, choices: reorder(choices))
        case let .sentence(tokens, blankIndex, choices, emoji):
            payload = .sentence(tokens: tokens, blankIndex: blankIndex, choices: reorder(choices), emoji: emoji)
        default:
            return activity
        }
        return Activity(key: activity.key, type: activity.type, unitId: activity.unitId, track: activity.track,
                        prompt: activity.prompt, spokenPrompt: activity.spokenPrompt, audioIds: activity.audioIds,
                        payload: payload, graphemesUsed: activity.graphemesUsed, trickyUsed: activity.trickyUsed)
        #else
        return activity
        #endif
    }
}
