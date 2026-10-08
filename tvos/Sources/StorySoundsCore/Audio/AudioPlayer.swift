import Foundation

/// Low-level engine (AVFoundation in production, a fake in tests). Main-thread use only.
public protocol AudioBackend: AnyObject {
    /// Starts playback; returns false when the file cannot be played (never throws, never crashes).
    func play(url: URL, channel: AudioChannel, volume: Float, rate: Float, loop: Bool) -> Bool
    func stop(channel: AudioChannel)
    func stopAll()
    func pauseAll()
    func resumeAll()
    func setVolume(_ volume: Float, channel: AudioChannel)
    var isAnythingPlaying: Bool { get }
    /// Called when a sound ends naturally.
    var onChannelFinished: ((AudioChannel) -> Void)? { get set }
}

/// Optional text-to-speech for WORDS and INSTRUCTIONS only. Output is always placeholder speech.
public protocol SpeechFallback: AnyObject {
    /// Must be true for every implementation: this is not authoritative pronunciation.
    var isPlaceholderSpeech: Bool { get }
    /// Implementations must refuse kinds for which `SpeechPolicy.isSpeechAllowed` is false (phonemes!). Returns false if refused.
    func speak(_ text: String, kind: AudioKind, volume: Float) -> Bool
    func stop()
    func pause()
    func resume()
    /// True while an utterance is queued or being spoken. Default: false (implementations that cannot tell).
    var isSpeaking: Bool { get }
    /// Registers a handler invoked (on the main thread) when an utterance finishes NATURALLY.
    /// It must NOT be invoked for an utterance that was cut off by `stop()` or by a newer `speak`.
    /// Default: ignored (callers then fall back to their timeout).
    func setOnFinished(_ handler: (() -> Void)?)
}

public extension SpeechFallback {
    var isSpeaking: Bool { return false }
    func setOnFinished(_ handler: (() -> Void)?) {}
}

public protocol AudioPlayer: AnyObject {
    var settings: LearnerSettings { get set }
    /// When true every request returns `.captionOnly` (or `.unavailable` for effects).
    var isMuted: Bool { get set }
    @discardableResult func play(_ audioId: String, options: PlaybackOptions) -> PlaybackResult
    /// Replays the last narration (phoneme/word/instruction), optionally slowed.
    @discardableResult func replay(slow: Bool) -> PlaybackResult
    func startMusic(url: URL)
    func stopMusic()
    func stopAll()
}

/// Ties library + planner + backend + state machine together. All decisions are in pure types, so tests use fakes.
public final class AudioPlaybackController: AudioPlayer {
    public var settings: LearnerSettings {
        didSet { applyVolumes() }
    }
    public var isMuted: Bool = false {
        didSet { if isMuted { stopAll() } }
    }
    public private(set) var machine = PlaybackStateMachine()
    public private(set) var lastNarrationRequest: (id: String, options: PlaybackOptions)?

    private let library: AudioLibrary
    private let backend: AudioBackend
    private let speech: SpeechFallback?
    private var musicURL: URL?
    private var narrationActive: Bool = false

    public init(library: AudioLibrary, backend: AudioBackend, speech: SpeechFallback? = nil, settings: LearnerSettings = LearnerSettings()) {
        self.library = library; self.backend = backend; self.speech = speech; self.settings = settings
        self.backend.onChannelFinished = { [weak self] ch in self?.channelFinished(ch) }
        self.speech?.setOnFinished { [weak self] in self?.speechFinished() }
    }

    private func channelFinished(_ channel: AudioChannel) {
        if channel == .narration && !(speech?.isSpeaking ?? false) { narrationActive = false }
        if !backend.isAnythingPlaying && !(speech?.isSpeaking ?? false) { machine.handle(.playbackFinished) }
    }

    private func speechFinished() {
        narrationActive = false
        if !backend.isAnythingPlaying { machine.handle(.playbackFinished) }
    }

    /// Cuts off whatever narration (recording OR speech) is in flight. Always called before new narration starts,
    /// so utterances never queue up behind each other.
    private func interruptNarration() {
        backend.stop(channel: .narration)
        speech?.stop()
        narrationActive = false
    }

    /// True while a narration clip (recording or placeholder speech) is playing.
    public var isNarrationActive: Bool { return narrationActive }

    /// Suspends until the current narration clip has finished, was stopped, or `timeout` seconds passed
    /// (a safety net for speech engines that never report completion). Cooperative with Task cancellation.
    public func waitForNarrationEnd(timeout: TimeInterval = 15) async {
        let deadline = Date().addingTimeInterval(max(0, timeout))
        while narrationActive && Date() < deadline && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
    }

    /// Plays `audioId` and returns once it has finished (immediately when nothing audible started: caption only etc.).
    @discardableResult
    public func playAndWait(_ audioId: String, options: PlaybackOptions = PlaybackOptions(), timeout: TimeInterval = 15) async -> PlaybackResult {
        let result = play(audioId, options: options)
        switch result {
        case .played, .spokenPlaceholder:
            await waitForNarrationEnd(timeout: timeout)
        case .captionOnly, .unavailable:
            break
        }
        return result
    }

    /// Plays ids one after another, each starting only after the previous clip has actually finished.
    /// Replaces fixed sleeps. `captionDwell` is how long to pause after an id that produced no sound (a caption is on screen).
    /// `perResult` lets the caller show captions. Stops early when the surrounding Task is cancelled.
    public func playSequenceAndWait(_ ids: [String], options: PlaybackOptions = PlaybackOptions(), gap: TimeInterval = 0.2,
                                    captionDwell: TimeInterval = 1.0, perResult: ((String, PlaybackResult) -> Void)? = nil) async {
        for id in ids {
            if Task.isCancelled { return }
            let result = await playAndWait(id, options: options)
            perResult?(id, result)
            if Task.isCancelled { return }
            switch result {
            case .played, .spokenPlaceholder:
                if gap > 0 { try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000)) }
            case .captionOnly, .unavailable:
                if captionDwell > 0 { try? await Task.sleep(nanoseconds: UInt64(captionDwell * 1_000_000_000)) }
            }
        }
    }

    private func applyVolumes() {
        for ch in AudioChannel.allCases { backend.setVolume(VolumeMixer.volume(for: ch, settings: settings), channel: ch) }
    }

    @discardableResult
    public func play(_ audioId: String, options: PlaybackOptions = PlaybackOptions()) -> PlaybackResult {
        let r = library.resolve(audioId)
        let channel = r.kind?.channel ?? .narration
        let volume = VolumeMixer.volume(for: channel, settings: settings)
        let speechOK = speech != nil && (r.kind.map(SpeechPolicy.isSpeechAllowed) ?? false)
        if let k = r.kind, k != .sfx { lastNarrationRequest = (audioId, options) }

        let plan = PlaybackPlanner.plan(for: r, muted: isMuted, channelVolume: volume, speechAvailable: speechOK, slow: options.slow)
        switch plan {
        case .nothing:
            return .unavailable
        case let .caption(label):
            return .captionOnly(label: label)
        case let .playFile(url, ch, rate, slowVariant):
            if ch == .narration { interruptNarration() }
            if backend.play(url: url, channel: ch, volume: volume, rate: rate, loop: false) {
                machine.handle(.playbackStarted)
                if ch == .narration { narrationActive = true }
                return .played(audioId: audioId, slowVariant: slowVariant)
            }
            // File could not be played: degrade without crashing, still respecting the phoneme policy.
            if let k = r.kind, SpeechPolicy.isSpeechAllowed(for: k), let sp = speech,
               sp.speak(r.label, kind: k, volume: volume) {
                machine.handle(.playbackStarted)
                narrationActive = true
                return .spokenPlaceholder(text: r.label)
            }
            return r.kind == .sfx ? .unavailable : .captionOnly(label: r.label)
        case let .speak(text):
            // Defence in depth: never speak a phoneme even if the planner were wrong.
            guard let k = r.kind, SpeechPolicy.isSpeechAllowed(for: k), let sp = speech else { return .captionOnly(label: r.label) }
            interruptNarration()
            if sp.speak(text, kind: k, volume: volume) {
                machine.handle(.playbackStarted)
                narrationActive = true
                return .spokenPlaceholder(text: text)
            }
            return .captionOnly(label: r.label)
        }
    }

    @discardableResult
    public func replay(slow: Bool = false) -> PlaybackResult {
        guard let last = lastNarrationRequest else { return .unavailable }
        return play(last.id, options: PlaybackOptions(slow: slow))
    }

    public func startMusic(url: URL) {
        musicURL = url
        guard !isMuted else { return }
        let v = VolumeMixer.volume(for: .music, settings: settings)
        guard v > 0.0001 else { return }
        if backend.play(url: url, channel: .music, volume: v, rate: 1.0, loop: true) { machine.handle(.playbackStarted) }
    }

    public func stopMusic() { musicURL = nil; backend.stop(channel: .music); channelFinished(.music) }

    public func stopAll() {
        backend.stopAll(); speech?.stop()
        narrationActive = false
        machine.handle(.userStop)
    }

    // MARK: System events (wired by AVAudioSessionObserver; callable directly from tests)

    public func handleInterruptionBegan() { apply(machine.handle(.interruptionBegan)) }
    public func handleInterruptionEnded(shouldResume: Bool) { apply(machine.handle(.interruptionEnded(shouldResume: shouldResume))) }
    public func handleRouteOldDeviceUnavailable() { apply(machine.handle(.routeOldDeviceUnavailable)) }
    /// For an explicit user action (e.g. pressing play) after a route change paused audio.
    public func userResume() { apply(machine.handle(.userResume)) }

    private func apply(_ action: PlaybackStateMachine.Action) {
        switch action {
        case .none: break
        case .pause: backend.pauseAll(); speech?.pause()
        case .resume: backend.resumeAll(); speech?.resume()
        case .stop: backend.stopAll(); speech?.stop(); narrationActive = false
        }
    }
}
