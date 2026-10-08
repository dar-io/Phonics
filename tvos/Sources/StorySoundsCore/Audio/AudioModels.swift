import Foundation

/// The three independent volume channels (driven by `LearnerSettings`).
public enum AudioChannel: String, CaseIterable, Sendable {
    case narration, music, effects
}

public extension AudioKind {
    /// Phonemes, words and instructions are narration; sfx are effects.
    var channel: AudioChannel { self == .sfx ? .effects : .narration }
}

/// Case-safe audio id derivation. Manifest ids are lower-case, but curriculum text is not ("I", "Mr", names such as "Zak").
/// Always derive word ids through here, never with `"w-" + text`.
public enum AudioIds {
    public static func word(_ text: String) -> String { return "w-" + text.lowercased() }
}

/// POLICY (enforced in code, covered by tests): isolated phoneme audio is NEVER synthesised.
/// Text-to-speech adds a schwa ("suh" for /s/) and cannot be trusted for pure sounds, so only recordings
/// (bundled or a parent's own) may be played for phonemes; otherwise the caller shows a caption only.
public enum SpeechPolicy {
    public static func isSpeechAllowed(for kind: AudioKind) -> Bool {
        switch kind {
        case .word, .instruction: return true
        case .phoneme, .sfx: return false
        }
    }
}

public enum ResolvedSource: Equatable, Sendable {
    case bundledFile
    case parentRecording
    /// In the manifest, but no usable recording (status placeholder, or the file is missing).
    case placeholder
    /// Id not present in the manifest at all.
    case unknownId
}

public struct ResolvedAudio: Equatable, Sendable {
    public let id: String
    public let kind: AudioKind?
    public let label: String
    public let status: AudioStatus?
    public let source: ResolvedSource
    public let url: URL?
    public let slowURL: URL?
    public var isPlayable: Bool { url != nil }
    public init(id: String, kind: AudioKind?, label: String, status: AudioStatus?, source: ResolvedSource, url: URL?, slowURL: URL?) {
        self.id = id; self.kind = kind; self.label = label; self.status = status; self.source = source; self.url = url; self.slowURL = slowURL
    }
}

public struct PlaybackOptions: Equatable, Sendable {
    public var slow: Bool
    public init(slow: Bool = false) { self.slow = slow }
}

public enum PlaybackResult: Equatable, Sendable {
    /// A real recording is playing.
    case played(audioId: String, slowVariant: Bool)
    /// No audio: show this text on screen instead (placeholder phoneme, muted mode, missing file).
    case captionOnly(label: String)
    /// Placeholder text-to-speech was used (words/instructions only). Always flagged.
    case spokenPlaceholder(text: String)
    /// Nothing to play and nothing to show (e.g. a placeholder sound effect).
    case unavailable

    public var isPlaceholderSpeech: Bool { if case .spokenPlaceholder = self { return true } else { return false } }
}

public enum PlaybackPlan: Equatable, Sendable {
    case playFile(url: URL, channel: AudioChannel, rate: Float, slowVariant: Bool)
    case speak(text: String)
    case caption(label: String)
    case nothing
}

/// Pure decision logic: no AVFoundation, fully testable.
public enum PlaybackPlanner {
    public static let defaultSlowRate: Float = 0.7

    public static func plan(for r: ResolvedAudio, muted: Bool, channelVolume: Float, speechAvailable: Bool,
                            slow: Bool, slowRate: Float = PlaybackPlanner.defaultSlowRate) -> PlaybackPlan {
        guard let kind = r.kind else { return .caption(label: r.label) }
        if muted || channelVolume <= 0.0001 {
            return kind == .sfx ? .nothing : .caption(label: r.label)
        }
        if let url = r.url {
            if slow {
                if let s = r.slowURL { return .playFile(url: s, channel: kind.channel, rate: 1.0, slowVariant: true) }
                return .playFile(url: url, channel: kind.channel, rate: slowRate, slowVariant: false)
            }
            return .playFile(url: url, channel: kind.channel, rate: 1.0, slowVariant: false)
        }
        // No recording available.
        if SpeechPolicy.isSpeechAllowed(for: kind) && speechAvailable { return .speak(text: r.label) }
        return kind == .sfx ? .nothing : .caption(label: r.label)
    }
}

/// Turns LearnerSettings into 0...1 channel volumes. Gentle mode (sound-sensitive) softens music and effects.
public enum VolumeMixer {
    public static let gentleMusicScale = 0.5
    public static let gentleEffectsScale = 0.6

    public static func volume(for channel: AudioChannel, settings: LearnerSettings) -> Float {
        var v: Double
        switch channel {
        case .narration: v = settings.narrationVolume
        case .music: v = settings.musicVolume * (settings.gentleMode ? gentleMusicScale : 1)
        case .effects: v = settings.effectsVolume * (settings.gentleMode ? gentleEffectsScale : 1)
        }
        if v.isNaN { v = 0 }
        return Float(min(1, max(0, v)))
    }
}

/// Pure state machine for interruptions / route changes (see AVAudioSession notifications).
/// Rules: an interruption pauses; when it ends WITH the shouldResume hint we resume, otherwise we stop.
/// A route loss (e.g. Bluetooth speaker disconnects) pauses and never auto-resumes: the adult/child restarts it.
public struct PlaybackStateMachine: Equatable, Sendable {
    public enum State: Equatable, Sendable { case idle, playing, pausedByInterruption, pausedByRoute }
    public enum Event: Equatable, Sendable {
        case playbackStarted, playbackFinished
        case interruptionBegan, interruptionEnded(shouldResume: Bool)
        case routeOldDeviceUnavailable
        case userResume, userStop
    }
    public enum Action: Equatable, Sendable { case none, pause, resume, stop }

    public private(set) var state: State = .idle
    public init() {}

    @discardableResult
    public mutating func handle(_ event: Event) -> Action {
        switch (state, event) {
        case (_, .playbackStarted):
            state = .playing; return .none
        case (.playing, .playbackFinished):
            state = .idle; return .none
        case (.playing, .interruptionBegan):
            state = .pausedByInterruption; return .pause
        case (.pausedByInterruption, .interruptionEnded(let shouldResume)):
            if shouldResume { state = .playing; return .resume }
            state = .idle; return .stop
        case (.playing, .routeOldDeviceUnavailable):
            state = .pausedByRoute; return .pause
        case (.pausedByInterruption, .routeOldDeviceUnavailable):
            state = .pausedByRoute; return .none
        case (.pausedByInterruption, .userResume), (.pausedByRoute, .userResume):
            state = .playing; return .resume
        case (.idle, .userStop):
            return .none
        case (_, .userStop):
            state = .idle; return .stop
        default:
            return .none
        }
    }
}
