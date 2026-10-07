import Foundation

/// Child-facing feedback. Always warm and tied to what the child just did; never failure language.
public enum Feedback {
    /// Words that must never appear in any feedback or narration string (checked by unit tests).
    public static let bannedWords: [String] = [
        "wrong", "incorrect", "fail", "failed", "failure", "mistake", "mistakes", "bad", "error", "errors",
        "nope", "stupid", "dumb", "silly", "poor", "worse", "worst"
    ]

    private static func choose(_ options: [String], key: String) -> String {
        if options.isEmpty { return "" }
        let i: Int = Int(SeededRNG.stableHash(key) % UInt64(options.count))
        return options[i]
    }

    /// Feedback for one answer. Deterministic for a given activity key.
    public static func text(for activity: Activity, answer: Answer) -> String {
        if answer.correct {
            if answer.support == .independent {
                return celebrate(activity)
            }
            return together(activity)
        }
        return support(activity)
    }

    private static func celebrate(_ a: Activity) -> String {
        switch a.payload {
        case let .choose(_, target, _):
            if a.type == .matchSoundGrapheme {
                return choose(["You matched the sound to \(target)!", "Yes! You know the sound for \(target)!"], key: a.key)
            }
            return choose(["You found the sound for \(target)!", "Yes! That is the sound for \(target)!"], key: a.key)
        case let .blend(_, word, _, _):
            return choose(["You sounded it out and found \(word)!", "Lovely blending! The word is \(word)!"], key: a.key)
        case let .order(_, _, word, _):
            return choose(["You put the sounds in order to make \(word)!", "The sounds fit together to make \(word)!"], key: a.key)
        case let .segment(word, _, _, _):
            return choose(["You split \(word) into its sounds!", "Great listening! You heard every sound in \(word)!"], key: a.key)
        case let .build(word, _, _, _):
            return choose(["You built \(word)!", "Look at that! You made the word \(word)!"], key: a.key)
        case let .picture(word, _):
            return choose(["You read \(word) and found its picture!", "Reading star! \(word) matches the picture!"], key: a.key)
        case let .tricky(word, _):
            return choose(["You found the tricky word \(word)!", "You know the tricky word \(word)!"], key: a.key)
        case .sentence:
            return choose(["You found the word that fits!", "Nice reading! That word fits the sentence!"], key: a.key)
        case .story:
            return choose(["You read the whole story!", "What a lovely story reader you are!"], key: a.key)
        case .fluency:
            return choose(["You read those words so smoothly!", "Lovely reading, one word after another!"], key: a.key)
        }
    }

    private static func together(_ a: Activity) -> String {
        switch a.payload {
        case let .choose(_, target, _):
            return choose(["We found \(target) together. Well done!", "Together we found the sound for \(target)!"], key: a.key)
        case let .blend(_, word, _, _):
            return choose(["We sounded out \(word) together. Well done!", "Together we found \(word)!"], key: a.key)
        case let .order(_, _, word, _), let .segment(word, _, _, _), let .build(word, _, _, _):
            return choose(["We did \(word) together. Well done!", "Together we worked out \(word)!"], key: a.key)
        case let .picture(word, _), let .tricky(word, _):
            return choose(["We read \(word) together. Well done!", "Together we found \(word)!"], key: a.key)
        case .sentence, .story, .fluency:
            return choose(["We read it together. Well done!", "Nice reading together!"], key: a.key)
        }
    }

    private static func support(_ a: Activity) -> String {
        switch a.payload {
        case let .choose(_, target, _):
            if a.type == .matchSoundGrapheme {
                return choose(["Let's look at \(target) together and listen for its sound.", "Let's listen to \(target) again together."], key: a.key)
            }
            return choose(["Let's listen again. Can you spot \(target)?", "Let's listen together. This sound is \(target)."], key: a.key)
        case let .blend(graphemes, _, _, _):
            let sounds: String = graphemes.joined(separator: " ... ")
            return choose(["Let's sound it out together: \(sounds).", "Let's say each sound, then blend them: \(sounds)."], key: a.key)
        case .order:
            return choose(["Let's say the sounds slowly, one at a time.", "Let's listen to the word again and find each sound."], key: a.key)
        case let .segment(word, _, _, _):
            return choose(["Let's stretch \(word) into its sounds together.", "Let's say \(word) slowly and listen for each sound."], key: a.key)
        case let .build(word, _, _, _):
            return choose(["Let's build \(word) together, one sound at a time.", "Let's listen to \(word) and find its letters together."], key: a.key)
        case let .picture(word, _):
            return choose(["Let's sound out \(word) together.", "Let's read \(word) slowly together."], key: a.key)
        case let .tricky(word, _):
            return choose(["This one is tricky. Let's look at \(word) together.", "Tricky words take time. Let's say \(word) together."], key: a.key)
        case .sentence:
            return choose(["Let's read the sentence together and listen for the word.", "Let's read it again together, nice and slowly."], key: a.key)
        case .story:
            return choose(["Let's look at this part together.", "Let's read this page again together."], key: a.key)
        case .fluency:
            return choose(["Let's read them together, nice and slowly.", "Let's read the words together, one at a time."], key: a.key)
        }
    }

    /// Short closing line for the end of a session.
    public static func sessionEnd(activitiesDone: Int) -> String {
        if activitiesDone <= 0 { return "That's all for today. See you soon!" }
        return "You did \(activitiesDone) activit\(activitiesDone == 1 ? "y" : "ies") today. That's all for now. See you soon!"
    }

    /// Everything the engine says that is not tied to a specific answer, for tests and caption review.
    public static func staticPhrases() -> [String] {
        return [sessionEnd(activitiesDone: 0), sessionEnd(activitiesDone: 1), sessionEnd(activitiesDone: 9)]
    }
}
