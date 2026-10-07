import XCTest
@testable import StorySoundsCore

// MARK: Fakes

final class FakeBackend: AudioBackend {
    struct Play: Equatable { let url: URL; let channel: AudioChannel; let volume: Float; let rate: Float; let loop: Bool }
    var plays: [Play] = []
    var playSucceeds = true
    var stopped: [AudioChannel] = []
    var pauseCount = 0, resumeCount = 0, stopAllCount = 0
    var volumes: [AudioChannel: Float] = [:]
    var playing = false
    var onChannelFinished: ((AudioChannel) -> Void)?
    var isAnythingPlaying: Bool { playing }

    func play(url: URL, channel: AudioChannel, volume: Float, rate: Float, loop: Bool) -> Bool {
        guard playSucceeds else { return false }
        plays.append(Play(url: url, channel: channel, volume: volume, rate: rate, loop: loop)); playing = true; return true
    }
    func stop(channel: AudioChannel) { stopped.append(channel) }
    func stopAll() { stopAllCount += 1; playing = false }
    func pauseAll() { pauseCount += 1 }
    func resumeAll() { resumeCount += 1 }
    func setVolume(_ volume: Float, channel: AudioChannel) { volumes[channel] = volume }
}

final class FakeSpeech: SpeechFallback {
    var isPlaceholderSpeech: Bool { true }
    var spoken: [(String, AudioKind)] = []
    var stops = 0, pauses = 0, resumes = 0
    func speak(_ text: String, kind: AudioKind, volume: Float) -> Bool { spoken.append((text, kind)); return true }
    func stop() { stops += 1 }
    func pause() { pauses += 1 }
    func resume() { resumes += 1 }
}

enum AudioFixtures {
    static func entry(_ id: String, _ kind: AudioKind, label: String? = nil, file: String? = nil, slow: String? = nil,
                      status: AudioStatus = .placeholder) -> AudioEntry {
        AudioEntry(id: id, kind: kind, label: label ?? id, file: file, slowFile: slow, status: status, note: nil)
    }
    static func manifest(_ entries: [AudioEntry]) -> AudioManifest { AudioManifest(version: 1, statement: "placeholder", entries: entries) }
    static let resolver: (String) -> URL? = { URL(string: "file:///bundle/\($0)") }

    static func library(_ entries: [AudioEntry], recordings: RecordingStore? = nil, resolver: @escaping (String) -> URL? = AudioFixtures.resolver) -> AudioLibrary {
        AudioLibrary(manifest: manifest(entries), bundleResolver: resolver, recordings: recordings)
    }
}

// MARK: Library

final class AudioLibraryTests: XCTestCase {
    func testPlaceholderEntryHasNoURLEvenIfFileListed() {
        let lib = AudioFixtures.library([AudioFixtures.entry("ph-g-s", .phoneme, label: "/s/", file: "s.m4a", status: .placeholder)])
        let r = lib.resolve("ph-g-s")
        XCTAssertEqual(r.source, .placeholder)
        XCTAssertNil(r.url)
    }

    func testRecordedBundledFileResolvesWithSlowVariant() {
        let lib = AudioFixtures.library([AudioFixtures.entry("w-cat", .word, file: "cat.m4a", slow: "cat-slow.m4a", status: .verified)])
        let r = lib.resolve("w-cat")
        XCTAssertEqual(r.source, .bundledFile)
        XCTAssertEqual(r.url?.lastPathComponent, "cat.m4a")
        XCTAssertEqual(r.slowURL?.lastPathComponent, "cat-slow.m4a")
        XCTAssertEqual(r.status, .verified)
    }

    func testMissingBundleFileFallsBackToPlaceholder() {
        let lib = AudioFixtures.library([AudioFixtures.entry("w-cat", .word, file: "cat.m4a", status: .recorded)], resolver: { _ in nil })
        XCTAssertEqual(lib.resolve("w-cat").source, .placeholder)
    }

    func testParentRecordingUsedWhenNoBundledAudio() {
        let rec = InMemoryRecordingStore()
        rec.set(URL(string: "file:///rec/s.m4a"), forAudioId: "ph-g-s")
        let lib = AudioFixtures.library([AudioFixtures.entry("ph-g-s", .phoneme, label: "/s/")], recordings: rec)
        let r = lib.resolve("ph-g-s")
        XCTAssertEqual(r.source, .parentRecording)
        XCTAssertEqual(r.status, .recorded, "a parent recording is never 'verified'")
    }

    func testBundledBeatsParentRecording() {
        let rec = InMemoryRecordingStore(); rec.set(URL(string: "file:///rec/x.m4a"), forAudioId: "w-x")
        let lib = AudioFixtures.library([AudioFixtures.entry("w-x", .word, file: "x.m4a", status: .verified)], recordings: rec)
        XCTAssertEqual(lib.resolve("w-x").source, .bundledFile)
    }

    func testUnknownId() {
        let r = AudioFixtures.library([]).resolve("nope")
        XCTAssertEqual(r.source, .unknownId)
        XCTAssertNil(r.kind)
    }

    func testStatusReportCountsByKind() {
        let rec = InMemoryRecordingStore(); rec.set(URL(string: "file:///rec/b.m4a"), forAudioId: "ph-b")
        let lib = AudioFixtures.library([
            AudioFixtures.entry("ph-a", .phoneme), AudioFixtures.entry("ph-b", .phoneme),
            AudioFixtures.entry("w-1", .word, file: "1.m4a", status: .recorded),
            AudioFixtures.entry("w-2", .word, file: "2.m4a", status: .verified),
            AudioFixtures.entry("w-3", .word),
            AudioFixtures.entry("sfx-1", .sfx),
        ], recordings: rec)
        let rep = lib.statusReport()
        XCTAssertEqual(rep.counts(for: .phoneme).placeholder, 1)
        XCTAssertEqual(rep.counts(for: .phoneme).recorded, 1)
        XCTAssertEqual(rep.counts(for: .word).recorded, 1)
        XCTAssertEqual(rep.counts(for: .word).verified, 1)
        XCTAssertEqual(rep.counts(for: .word).placeholder, 1)
        XCTAssertEqual(rep.counts(for: .sfx).placeholder, 1)
        XCTAssertEqual(rep.counts(for: .instruction).total, 0)
        XCTAssertEqual(rep.total.total, 6)
        XCTAssertEqual(rep.parentRecordingCount, 1)
        XCTAssertFalse(rep.isAllPlaceholder)
        XCTAssertEqual(rep.summaryLines.count, 4)
    }

    func testBundledManifestIsReportedAllPlaceholderAndDisclaimerDoesNotClaimApproval() throws {
        let manifest = try AudioManifest.loadBundled()
        let lib = AudioLibrary(manifest: manifest, bundleResolver: { _ in nil })
        let rep = lib.statusReport()
        XCTAssertTrue(rep.isAllPlaceholder)
        XCTAssertEqual(rep.counts(for: .phoneme).total, manifest.entries.filter { $0.kind == .phoneme }.count)
        XCTAssertTrue(AudioStatusReport.disclaimer.contains("not Little Wandle approved"))
    }
}

// MARK: Planner / mixer / policy

final class PlaybackPlannerTests: XCTestCase {
    private func resolved(_ kind: AudioKind, url: String? = nil, slow: String? = nil) -> ResolvedAudio {
        ResolvedAudio(id: "id", kind: kind, label: "lbl", status: url == nil ? .placeholder : .recorded,
                      source: url == nil ? .placeholder : .bundledFile, url: url.flatMap { URL(string: $0) }, slowURL: slow.flatMap { URL(string: $0) })
    }

    func testPhonemePlaceholderIsCaptionOnlyEvenWhenSpeechAvailable() {
        let p = PlaybackPlanner.plan(for: resolved(.phoneme), muted: false, channelVolume: 1, speechAvailable: true, slow: false)
        XCTAssertEqual(p, .caption(label: "lbl"))
    }

    func testWordAndInstructionPlaceholderMaySpeakOnlyIfAvailable() {
        XCTAssertEqual(PlaybackPlanner.plan(for: resolved(.word), muted: false, channelVolume: 1, speechAvailable: true, slow: false), .speak(text: "lbl"))
        XCTAssertEqual(PlaybackPlanner.plan(for: resolved(.instruction), muted: false, channelVolume: 1, speechAvailable: true, slow: false), .speak(text: "lbl"))
        XCTAssertEqual(PlaybackPlanner.plan(for: resolved(.word), muted: false, channelVolume: 1, speechAvailable: false, slow: false), .caption(label: "lbl"))
    }

    func testSfxPlaceholderIsNothing() {
        XCTAssertEqual(PlaybackPlanner.plan(for: resolved(.sfx), muted: false, channelVolume: 1, speechAvailable: true, slow: false), .nothing)
    }

    func testMutedOrZeroVolumeGivesCaptions() {
        let r = resolved(.word, url: "file:///a.m4a")
        XCTAssertEqual(PlaybackPlanner.plan(for: r, muted: true, channelVolume: 1, speechAvailable: true, slow: false), .caption(label: "lbl"))
        XCTAssertEqual(PlaybackPlanner.plan(for: r, muted: false, channelVolume: 0, speechAvailable: true, slow: false), .caption(label: "lbl"))
        XCTAssertEqual(PlaybackPlanner.plan(for: resolved(.sfx, url: "file:///a.m4a"), muted: true, channelVolume: 1, speechAvailable: false, slow: false), .nothing)
    }

    func testSlowUsesSlowFileElseReducedRate() {
        let both = resolved(.phoneme, url: "file:///a.m4a", slow: "file:///a-slow.m4a")
        XCTAssertEqual(PlaybackPlanner.plan(for: both, muted: false, channelVolume: 1, speechAvailable: false, slow: true),
                       .playFile(url: URL(string: "file:///a-slow.m4a")!, channel: .narration, rate: 1.0, slowVariant: true))
        let only = resolved(.phoneme, url: "file:///a.m4a")
        XCTAssertEqual(PlaybackPlanner.plan(for: only, muted: false, channelVolume: 1, speechAvailable: false, slow: true),
                       .playFile(url: URL(string: "file:///a.m4a")!, channel: .narration, rate: PlaybackPlanner.defaultSlowRate, slowVariant: false))
    }

    func testUnknownIdIsCaption() {
        let r = ResolvedAudio(id: "zzz", kind: nil, label: "zzz", status: nil, source: .unknownId, url: nil, slowURL: nil)
        XCTAssertEqual(PlaybackPlanner.plan(for: r, muted: false, channelVolume: 1, speechAvailable: true, slow: false), .caption(label: "zzz"))
    }

    func testSpeechPolicy() {
        XCTAssertFalse(SpeechPolicy.isSpeechAllowed(for: .phoneme))
        XCTAssertFalse(SpeechPolicy.isSpeechAllowed(for: .sfx))
        XCTAssertTrue(SpeechPolicy.isSpeechAllowed(for: .word))
        XCTAssertTrue(SpeechPolicy.isSpeechAllowed(for: .instruction))
    }

    func testChannelsAndVolumeMixer() {
        XCTAssertEqual(AudioKind.sfx.channel, .effects)
        XCTAssertEqual(AudioKind.phoneme.channel, .narration)
        var s = LearnerSettings()
        s.narrationVolume = 0.5; s.musicVolume = 2; s.effectsVolume = -1
        XCTAssertEqual(VolumeMixer.volume(for: .narration, settings: s), 0.5, accuracy: 0.001)
        XCTAssertEqual(VolumeMixer.volume(for: .music, settings: s), 1.0, accuracy: 0.001)
        XCTAssertEqual(VolumeMixer.volume(for: .effects, settings: s), 0.0, accuracy: 0.001)
        s.musicVolume = 0.8; s.gentleMode = true
        XCTAssertEqual(VolumeMixer.volume(for: .music, settings: s), 0.4, accuracy: 0.001)
    }
}

// MARK: State machine

final class PlaybackStateMachineTests: XCTestCase {
    func testInterruptionPausesThenResumesWhenHinted() {
        var m = PlaybackStateMachine()
        m.handle(.playbackStarted)
        XCTAssertEqual(m.handle(.interruptionBegan), .pause)
        XCTAssertEqual(m.state, .pausedByInterruption)
        XCTAssertEqual(m.handle(.interruptionEnded(shouldResume: true)), .resume)
        XCTAssertEqual(m.state, .playing)
    }

    func testInterruptionEndedWithoutHintStops() {
        var m = PlaybackStateMachine()
        m.handle(.playbackStarted); m.handle(.interruptionBegan)
        XCTAssertEqual(m.handle(.interruptionEnded(shouldResume: false)), .stop)
        XCTAssertEqual(m.state, .idle)
    }

    func testRouteLossPausesAndNeverAutoResumes() {
        var m = PlaybackStateMachine()
        m.handle(.playbackStarted)
        XCTAssertEqual(m.handle(.routeOldDeviceUnavailable), .pause)
        XCTAssertEqual(m.handle(.interruptionEnded(shouldResume: true)), .none)
        XCTAssertEqual(m.state, .pausedByRoute)
        XCTAssertEqual(m.handle(.userResume), .resume)
        XCTAssertEqual(m.state, .playing)
    }

    func testRouteLossDuringInterruptionDoesNotResumeAfterwards() {
        var m = PlaybackStateMachine()
        m.handle(.playbackStarted); m.handle(.interruptionBegan)
        XCTAssertEqual(m.handle(.routeOldDeviceUnavailable), .none)
        XCTAssertEqual(m.handle(.interruptionEnded(shouldResume: true)), .none)
        XCTAssertEqual(m.state, .pausedByRoute)
    }

    func testEventsWhileIdleAreHarmless() {
        var m = PlaybackStateMachine()
        XCTAssertEqual(m.handle(.interruptionBegan), .none)
        XCTAssertEqual(m.handle(.interruptionEnded(shouldResume: true)), .none)
        XCTAssertEqual(m.handle(.routeOldDeviceUnavailable), .none)
        XCTAssertEqual(m.handle(.userStop), .none)
        XCTAssertEqual(m.handle(.playbackFinished), .none)
        XCTAssertEqual(m.state, .idle)
    }

    func testFinishReturnsToIdleAndStopAlwaysStops() {
        var m = PlaybackStateMachine()
        m.handle(.playbackStarted); m.handle(.playbackFinished)
        XCTAssertEqual(m.state, .idle)
        m.handle(.playbackStarted)
        XCTAssertEqual(m.handle(.userStop), .stop)
    }
}

// MARK: Controller with fakes

final class AudioPlaybackControllerTests: XCTestCase {
    private func make(_ entries: [AudioEntry], speech: FakeSpeech? = FakeSpeech(), backend: FakeBackend = FakeBackend())
        -> (AudioPlaybackController, FakeBackend, FakeSpeech?) {
        let c = AudioPlaybackController(library: AudioFixtures.library(entries), backend: backend, speech: speech)
        return (c, backend, speech)
    }

    func testPhonemePlaceholderNeverSpeaksAndReturnsCaption() {
        let (c, b, s) = make([AudioFixtures.entry("ph-g-s", .phoneme, label: "/s/")])
        XCTAssertEqual(c.play("ph-g-s"), .captionOnly(label: "/s/"))
        XCTAssertTrue(s!.spoken.isEmpty)
        XCTAssertTrue(b.plays.isEmpty)
    }

    func testEveryBundledPhonemeIsCaptionOnlyAndNeverSynthesised() throws {
        let manifest = try AudioManifest.loadBundled()
        let backend = FakeBackend(), speech = FakeSpeech()
        let c = AudioPlaybackController(library: AudioLibrary(manifest: manifest, bundleResolver: { _ in nil }), backend: backend, speech: speech)
        for e in manifest.entries where e.kind == .phoneme {
            guard case .captionOnly(let label) = c.play(e.id) else { return XCTFail("phoneme \(e.id) was not caption-only") }
            XCTAssertEqual(label, e.label)
        }
        XCTAssertTrue(speech.spoken.isEmpty)
    }

    func testFailedFilePlaybackOfPhonemeDegradesToCaptionNotSpeech() {
        let backend = FakeBackend(); backend.playSucceeds = false
        let (c, _, s) = make([AudioFixtures.entry("ph-g-s", .phoneme, label: "/s/", file: "s.m4a", status: .recorded)], backend: backend)
        XCTAssertEqual(c.play("ph-g-s"), .captionOnly(label: "/s/"))
        XCTAssertTrue(s!.spoken.isEmpty)
    }

    func testWordPlaceholderUsesFlaggedSpeech() {
        let (c, _, s) = make([AudioFixtures.entry("w-cat", .word, label: "cat")])
        let r = c.play("w-cat")
        XCTAssertEqual(r, .spokenPlaceholder(text: "cat"))
        XCTAssertTrue(r.isPlaceholderSpeech)
        XCTAssertEqual(s!.spoken.first?.1, .word)
        XCTAssertTrue(s!.isPlaceholderSpeech)
    }

    func testWordWithoutSpeechFallbackIsCaption() {
        let (c, _, _) = make([AudioFixtures.entry("w-cat", .word, label: "cat")], speech: nil)
        XCTAssertEqual(c.play("w-cat"), .captionOnly(label: "cat"))
    }

    func testRecordedAudioPlaysOnNarrationChannelWithVolume() {
        var settings = LearnerSettings(); settings.narrationVolume = 0.6
        let (c, b, _) = make([AudioFixtures.entry("ph-g-s", .phoneme, file: "s.m4a", status: .recorded)])
        c.settings = settings
        XCTAssertEqual(c.play("ph-g-s"), .played(audioId: "ph-g-s", slowVariant: false))
        XCTAssertEqual(b.plays.first?.channel, .narration)
        XCTAssertEqual(b.plays.first?.volume ?? 0, 0.6, accuracy: 0.001)
        XCTAssertEqual(c.machine.state, .playing)
    }

    func testSfxUsesEffectsChannelAndPlaceholderSfxIsUnavailable() {
        let (c, b, _) = make([AudioFixtures.entry("sfx-ok", .sfx, file: "ok.m4a", status: .recorded), AudioFixtures.entry("sfx-ph", .sfx)])
        _ = c.play("sfx-ok")
        XCTAssertEqual(b.plays.first?.channel, .effects)
        XCTAssertEqual(c.play("sfx-ph"), .unavailable)
    }

    func testMutedReturnsCaptionOnlyAndPlaysNothing() {
        let (c, b, s) = make([AudioFixtures.entry("w-cat", .word, label: "cat", file: "c.m4a", status: .recorded)])
        c.isMuted = true
        XCTAssertEqual(c.play("w-cat"), .captionOnly(label: "cat"))
        XCTAssertTrue(b.plays.isEmpty)
        XCTAssertTrue(s!.spoken.isEmpty)
    }

    func testReplayAndSlowReplay() {
        let (c, b, _) = make([AudioFixtures.entry("w-cat", .word, file: "c.m4a", status: .recorded)])
        XCTAssertEqual(c.replay(), .unavailable, "nothing played yet")
        _ = c.play("w-cat")
        _ = c.replay()
        _ = c.replay(slow: true)
        XCTAssertEqual(b.plays.count, 3)
        XCTAssertEqual(b.plays[1].rate, 1.0)
        XCTAssertEqual(b.plays[2].rate, PlaybackPlanner.defaultSlowRate)
    }

    func testSfxDoesNotOverwriteReplayTarget() {
        let (c, b, _) = make([AudioFixtures.entry("w-cat", .word, file: "c.m4a", status: .recorded), AudioFixtures.entry("sfx", .sfx, file: "s.m4a", status: .recorded)])
        _ = c.play("w-cat"); _ = c.play("sfx"); _ = c.replay()
        XCTAssertEqual(b.plays.last?.url.lastPathComponent, "c.m4a")
    }

    func testSettingsPushVolumesToAllThreeChannels() {
        let (c, b, _) = make([])
        var s = LearnerSettings(); s.narrationVolume = 0.3; s.musicVolume = 0.2; s.effectsVolume = 0.1
        c.settings = s
        XCTAssertEqual(b.volumes[.narration] ?? -1, 0.3, accuracy: 0.001)
        XCTAssertEqual(b.volumes[.music] ?? -1, 0.2, accuracy: 0.001)
        XCTAssertEqual(b.volumes[.effects] ?? -1, 0.1, accuracy: 0.001)
    }

    func testInterruptionAndRouteChangeDriveBackend() {
        let (c, b, s) = make([AudioFixtures.entry("w-cat", .word, file: "c.m4a", status: .recorded)])
        _ = c.play("w-cat")
        c.handleInterruptionBegan()
        XCTAssertEqual(b.pauseCount, 1); XCTAssertEqual(s!.pauses, 1)
        c.handleInterruptionEnded(shouldResume: true)
        XCTAssertEqual(b.resumeCount, 1)
        c.handleRouteOldDeviceUnavailable()
        XCTAssertEqual(b.pauseCount, 2)
        c.handleInterruptionEnded(shouldResume: true)
        XCTAssertEqual(b.resumeCount, 1, "route loss must not auto-resume")
        c.userResume()
        XCTAssertEqual(b.resumeCount, 2)
    }

    func testFinishCallbackReturnsMachineToIdle() {
        let (c, b, _) = make([AudioFixtures.entry("w-cat", .word, file: "c.m4a", status: .recorded)])
        _ = c.play("w-cat")
        b.playing = false
        b.onChannelFinished?(.narration)
        XCTAssertEqual(c.machine.state, .idle)
    }

    func testMusicLoopsOnMusicChannelAndRespectsMute() {
        let (c, b, _) = make([])
        c.startMusic(url: URL(string: "file:///m.m4a")!)
        XCTAssertEqual(b.plays.first?.channel, .music)
        XCTAssertEqual(b.plays.first?.loop, true)
        c.isMuted = true
        XCTAssertEqual(b.stopAllCount, 1)
        c.startMusic(url: URL(string: "file:///m.m4a")!)
        XCTAssertEqual(b.plays.count, 1)
    }
}

#if canImport(AVFoundation)
import AVFoundation
final class AVSpeechPolicyTests: XCTestCase {
    func testAVSpeechFallbackRefusesPhonemesAndIsFlagged() {
        let s = AVSpeechFallback()
        XCTAssertTrue(s.isPlaceholderSpeech)
        XCTAssertFalse(s.speak("s", kind: .phoneme, volume: 1))
        XCTAssertFalse(s.speak("ding", kind: .sfx, volume: 1))
    }
}
#endif
