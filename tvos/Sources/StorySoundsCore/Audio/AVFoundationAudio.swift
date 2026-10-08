import Foundation

#if canImport(AVFoundation)
import AVFoundation

/// AVAudioPlayer-based backend with three independent channels. Use from the main thread.
public final class AVAudioPlayerBackend: NSObject, AudioBackend, AVAudioPlayerDelegate {
    public var onChannelFinished: ((AudioChannel) -> Void)?

    private var narration: AVAudioPlayer?
    private var music: AVAudioPlayer?
    private var effects: [AVAudioPlayer] = []
    private var pausedPlayers: [AVAudioPlayer] = []
    private var volumes: [AudioChannel: Float] = [.narration: 1, .music: 1, .effects: 1]
    private let mixWithOthers: Bool
    private var sessionConfigured = false

    /// - mixWithOthers: when true the app's audio mixes with other apps (ambient-style) instead of interrupting them.
    public init(mixWithOthers: Bool = true) { self.mixWithOthers = mixWithOthers; super.init() }

    private func configureSessionIfNeeded() {
        #if os(tvOS) || os(iOS) || os(visionOS)
        guard !sessionConfigured else { return }
        sessionConfigured = true
        let s = AVAudioSession.sharedInstance()
        var opts: AVAudioSession.CategoryOptions = []
        if mixWithOthers { opts.insert(.mixWithOthers) }
        try? s.setCategory(.playback, mode: .default, options: opts)
        try? s.setActive(true)
        #endif
    }

    public var isAnythingPlaying: Bool {
        (narration?.isPlaying ?? false) || (music?.isPlaying ?? false) || effects.contains { $0.isPlaying } || !pausedPlayers.isEmpty
    }

    public func play(url: URL, channel: AudioChannel, volume: Float, rate: Float, loop: Bool) -> Bool {
        configureSessionIfNeeded()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.enableRate = true
            p.rate = min(2.0, max(0.5, rate))
            p.volume = volume
            p.numberOfLoops = loop ? -1 : 0
            guard p.prepareToPlay(), p.play() else { return false }
            switch channel {
            case .narration: narration?.stop(); narration = p
            case .music: music?.stop(); music = p
            case .effects: effects.removeAll { !$0.isPlaying }; effects.append(p)
            }
            prunePaused()
            return true
        } catch {
            return false
        }
    }

    public func stop(channel: AudioChannel) {
        switch channel {
        case .narration: narration?.stop(); narration = nil
        case .music: music?.stop(); music = nil
        case .effects: effects.forEach { $0.stop() }; effects.removeAll()
        }
        prunePaused()
    }

    private func prunePaused() { pausedPlayers.removeAll { !isTracked($0) } }
    private func isTracked(_ p: AVAudioPlayer) -> Bool { p === narration || p === music || effects.contains { $0 === p } }

    public func stopAll() {
        stop(channel: .narration); stop(channel: .music); stop(channel: .effects)
        pausedPlayers.removeAll()
    }

    public func pauseAll() {
        let all = [narration, music].compactMap { $0 } + effects
        pausedPlayers = all.filter { $0.isPlaying }
        pausedPlayers.forEach { $0.pause() }
    }

    public func resumeAll() {
        let toResume = pausedPlayers
        pausedPlayers.removeAll()
        configureSessionIfNeeded()
        toResume.forEach { _ = $0.play() }
    }

    public func setVolume(_ volume: Float, channel: AudioChannel) {
        volumes[channel] = volume
        switch channel {
        case .narration: narration?.volume = volume
        case .music: music?.volume = volume
        case .effects: effects.forEach { $0.volume = volume }
        }
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        var ch: AudioChannel = .effects
        if player === narration { narration = nil; ch = .narration }
        else if player === music { music = nil; ch = .music }
        else { effects.removeAll { $0 === player } }
        onChannelFinished?(ch)
    }

    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        audioPlayerDidFinishPlaying(player, successfully: false)
    }
}

/// Placeholder text-to-speech. Refuses phonemes. Every utterance is placeholder speech, not authoritative pronunciation.
/// A new `speak` always cuts off whatever is still being spoken (utterances never queue up), and completion of an
/// utterance is reported through `setOnFinished` (only for utterances that ended naturally).
public final class AVSpeechFallback: NSObject, SpeechFallback, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var current: AVSpeechUtterance?
    private var onFinished: (() -> Void)?
    public let isPlaceholderSpeech: Bool = true
    public var languageCode: String = "en-GB"

    public override init() {
        super.init()
        synth.delegate = self
    }

    public var isSpeaking: Bool { return current != nil }

    public func setOnFinished(_ handler: (() -> Void)?) { onFinished = handler }

    public func speak(_ text: String, kind: AudioKind, volume: Float) -> Bool {
        guard SpeechPolicy.isSpeechAllowed(for: kind) else { return false }
        // Cut off in-flight speech first. Clearing `current` before stopping makes the old utterance's cancel callback inert.
        current = nil
        if synth.isSpeaking || synth.isPaused { _ = synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: languageCode)
        u.volume = volume
        current = u
        synth.speak(u)
        return true
    }
    public func stop() {
        current = nil
        _ = synth.stopSpeaking(at: .immediate)
    }
    public func pause() { _ = synth.pauseSpeaking(at: .immediate) }
    public func resume() { _ = synth.continueSpeaking() }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard utterance === current else { return }
        current = nil
        onFinished?()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // A cancelled utterance that is still "current" was cancelled by the system (not by stop/speak): treat as finished.
        guard utterance === current else { return }
        current = nil
        onFinished?()
    }
}

#if os(tvOS) || os(iOS) || os(visionOS)
/// Listens for AVAudioSession interruption and route-change notifications and forwards them to the controller.
public final class AVAudioSessionObserver {
    private var tokens: [NSObjectProtocol] = []
    private weak var controller: AudioPlaybackController?

    public init(controller: AudioPlaybackController, center: NotificationCenter = .default) {
        self.controller = controller
        tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            self?.handleInterruption(n)
        })
        tokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            self?.handleRouteChange(n)
        })
    }

    deinit { tokens.forEach { NotificationCenter.default.removeObserver($0) } }

    private func handleInterruption(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            controller?.handleInterruptionBegan()
        case .ended:
            let optRaw = (n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            controller?.handleInterruptionEnded(shouldResume: AVAudioSession.InterruptionOptions(rawValue: optRaw).contains(.shouldResume))
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        if reason == .oldDeviceUnavailable { controller?.handleRouteOldDeviceUnavailable() }
    }
}
#endif
#endif
