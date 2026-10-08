import Foundation
import SwiftUI
import StorySoundsCore
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Top-level navigation. Root screens (onboarding, home) deliberately let the system handle Menu (leaves the app).
enum Route: Equatable {
    case onboarding
    case home
    case baseline
    case session
    case summary(SessionSummary)
    case parent
}

/// Launch arguments understood by the DEBUG build. They exist so UI tests are deterministic.
/// In Release builds `init(arguments:)` ignores its input entirely, so a shipping app can never be switched into
/// test behaviour (or wiped) by a launch argument. CI builds Debug, so the UI tests still work.
///  - `-uitest-reset`              wipe every stored learner / setting at launch
///  - `-uitest-inmemory`           use in-memory stores (nothing is written to disk)
///  - `-uitest-reduce-motion`      behave as if Reduce Motion / gentle mode were on
///  - `-uitest-no-audio`           silent backend and no text-to-speech (captions only)
///  - `-uitest-fast-review`        treat "now" as +2 days (exercises delayed review)
///  - `-uitest-day-offset N`       treat "now" as +N days
///  - `-uitest-session-minutes N`  override the session length
///  - `-uitest-seed N`             fixed session seed (repeatable lessons)
///  - `-uitest-force-load-error`   show the friendly load-error screen (Retry clears the flag)
///  - `-uitest-first-choice-wrong` arrange choices so `choice.0` is wrong (deterministic "do it together" path)
struct LaunchOptions: Equatable {
    var reset = false
    var inMemory = false
    var reduceMotion = false
    var noAudio = false
    var dayOffset = 0
    /// UI tests only: skip the press-and-hold step of the parent gate (the adult question is still required).
    var skipGateHold = false
    /// UI tests only: override the session length in minutes.
    var sessionMinutes: Int?
    /// UI tests only: fixed seed for session planning.
    var seed: UInt64?
    /// UI tests only: pretend the lessons could not be loaded.
    var forceLoadError = false
    /// UI tests only: put the correct answer last and make `choice.0` a wrong one.
    var firstChoiceWrong = false

    init(arguments: [String] = []) {
        #if DEBUG
        reset = arguments.contains("-uitest-reset")
        inMemory = arguments.contains("-uitest-inmemory")
        reduceMotion = arguments.contains("-uitest-reduce-motion")
        noAudio = arguments.contains("-uitest-no-audio")
        skipGateHold = arguments.contains("-uitest-parent-gate-pass")
        forceLoadError = arguments.contains("-uitest-force-load-error")
        firstChoiceWrong = arguments.contains("-uitest-first-choice-wrong")
        if let i = arguments.firstIndex(of: "-uitest-session-minutes"), i + 1 < arguments.count, let n = Int(arguments[i + 1]), n > 0 {
            sessionMinutes = n
        }
        if let i = arguments.firstIndex(of: "-uitest-seed"), i + 1 < arguments.count, let n = UInt64(arguments[i + 1]) {
            seed = n
        }
        if arguments.contains("-uitest-fast-review") { dayOffset = 2 }
        if let i = arguments.firstIndex(of: "-uitest-day-offset"), i + 1 < arguments.count, let n = Int(arguments[i + 1]) {
            dayOffset = n
        }
        #endif
    }
}

/// Which saved profile the app opens. Reads are explicit about failure: an unreadable profile is never silently
/// replaced by a new one (that would orphan the child's progress).
/// TODO(core): when `LearnerStore.activeProfileId()/setActiveProfileId(_:)/loadMostRecentValid()` land in
/// StorySoundsCore, delegate to them and delete this local stand-in (same behaviour, stored under its own key).
enum ProfileSelection {
    case empty
    case loaded(LearnerSnapshot)
    case unreadable

    private static let activeKey = StorageNamespace.root + "ui.activeProfile"

    static func activeId(_ kv: KeyValueStoring) -> String? {
        guard let d = kv.data(forKey: activeKey), let s = String(data: d, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    static func setActiveId(_ id: String, in kv: KeyValueStoring) {
        try? kv.setData(Data(id.utf8), forKey: activeKey)
    }

    /// Newest evidence of use, so "most recent valid profile" does not depend on key order.
    static func recency(_ s: LearnerSnapshot) -> Date {
        var d = s.profile.createdAt
        if let a = s.attempts.map({ $0.at }).max(), a > d { d = a }
        if let e = s.sessions.map({ $0.endedAt ?? $0.startedAt }).max(), e > d { d = e }
        return d
    }

    static func choose(store: LearnerStore, kv: KeyValueStoring) -> ProfileSelection {
        let ids: [String]
        do {
            ids = try store.listProfileIds()
        } catch {
            return .unreadable
        }
        if ids.isEmpty { return .empty }
        if let active = activeId(kv), ids.contains(active) {
            do {
                if let s = try store.load(profileId: active) { return .loaded(s) }
            } catch {
                // The profile we know is the live one cannot be read: do NOT fall back to another or start fresh.
                return .unreadable
            }
        }
        var best: LearnerSnapshot?
        var failed = false
        for id in ids {
            do {
                guard let s = try store.load(profileId: id) else { continue }
                if let b = best, recency(b) >= recency(s) { continue }
                best = s
            } catch {
                failed = true
            }
        }
        if let b = best { return .loaded(b) }
        return failed ? .unreadable : .empty
    }
}

/// A backend that never produces sound (UI tests / `-uitest-no-audio`). Returning false from `play` makes the
/// controller fall back to captions, exactly like a missing recording.
final class SilentAudioBackend: AudioBackend {
    var onChannelFinished: ((AudioChannel) -> Void)?
    var isAnythingPlaying: Bool { false }
    func play(url: URL, channel: AudioChannel, volume: Float, rate: Float, loop: Bool) -> Bool { false }
    func stop(channel: AudioChannel) {}
    func stopAll() {}
    func pauseAll() {}
    func resumeAll() {}
    func setVolume(_ volume: Float, channel: AudioChannel) {}
}

/// THE integration point. The child UI and the parent UI both read and write learner state only through this object.
@MainActor
final class AppEnvironment: ObservableObject {
    // MARK: Content and audio
    let curriculum: Curriculum
    let index: CurriculumIndex
    let manifest: AudioManifest
    let library: AudioLibrary
    let audio: AudioPlaybackController

    // MARK: Storage (exposed for the parent area: backup, privacy, deletion)
    let store: LearnerStore
    let localKeyValue: KeyValueStoring
    let privacy: PrivacySettingsStore
    let backup: BackupService
    let coordinator: PersistenceCoordinator
    /// Household user scope. HOOK: when the app adopts tvOS user profiles, derive this from
    /// `TVUserManager` (TVServices) in `AppEnvironment.currentUserScope()` below. It is nil today, which means a
    /// single shared household profile. The scope only changes the storage key prefix; nothing else depends on it.
    let userScope: String?
    let options: LaunchOptions
    /// Non-nil when the bundled lessons could not be loaded. The root view then shows a friendly retry screen.
    let loadFailure: String?

    // MARK: Observable state
    @Published private(set) var snapshot: LearnerSnapshot
    @Published var route: Route
    /// Sound on/off for the whole app (kept separate from the volumes so turning it back on restores them).
    @Published private(set) var soundOn: Bool
    /// Caption for a sound that has no recording yet (phonemes are never synthesised). Only set when the parent's
    /// Captions setting is on; stays until the next prompt or sound, or about 4.5 s.
    @Published private(set) var soundCaption: String? = nil
    /// True after a save failed; the parent area can mention it. Cleared after a successful save.
    @Published private(set) var saveProblem = false

    private var sequenceTask: Task<Void, Never>?
    private var sequenceGeneration = 0
    private var captionTask: Task<Void, Never>?
    private var sessionObserver: AnyObject?
    private static let soundKey = "storysounds.ui.soundOn"

    // MARK: Factory

    static func make(arguments: [String] = CommandLine.arguments) -> AppEnvironment {
        let options = LaunchOptions(arguments: arguments)
        var failure: String?
        var curriculum = AppEnvironment.emptyCurriculum()
        do {
            curriculum = try Curriculum.loadBundled()
        } catch {
            failure = AppEnvironment.storiesUnavailableMessage
        }
        #if DEBUG
        if options.forceLoadError { failure = AppEnvironment.storiesUnavailableMessage }
        #endif
        let manifest: AudioManifest = (try? AudioManifest.loadBundled()) ?? AppEnvironment.blankManifest()
        return AppEnvironment(options: options, curriculum: curriculum, manifest: manifest, failure: failure)
    }

    /// Wren's line on the recovery screen when the lessons cannot be opened.
    static let storiesUnavailableMessage = "Oh dear, I can't find our stories right now. Let's try again."
    /// Wren's line when saved progress exists but cannot be read. Nothing is overwritten.
    static let progressUnreadableMessage = "Hmm, I can't open our saved adventure just now. Your stars are safe. Let's try again."

    /// HOOK for tvOS household users (see `userScope`). Intentionally returns nil; TVServices is not imported.
    static func currentUserScope() -> String? { nil }

    private static func emptyCurriculum() -> Curriculum {
        Curriculum(schemaVersion: CurriculumSchema.version, contentVersion: "none", units: [], words: [],
                   trickyWords: [], sentences: [], stories: [])
    }

    private static func blankManifest() -> AudioManifest {
        let json = "{\"version\":1,\"statement\":\"\",\"entries\":[]}"
        do {
            return try JSONDecoder().decode(AudioManifest.self, from: Data(json.utf8))
        } catch {
            fatalError("Built-in constant manifest must decode")
        }
    }

    private static func freshSnapshot(contentVersion: String) -> LearnerSnapshot {
        let profile = LearnerProfile(id: UUID().uuidString, nickname: "Reader", createdAt: Date(), contentVersion: contentVersion)
        return LearnerSnapshot(profile: profile)
    }

    // MARK: Init

    private init(options: LaunchOptions, curriculum: Curriculum, manifest: AudioManifest, failure: String?) {
        let scope = AppEnvironment.currentUserScope()
        let kv: KeyValueStoring = options.inMemory ? InMemoryKeyValueStore() : UserDefaultsKeyValueStore()
        let store = KeyValueLearnerStore(keyValue: kv, userScope: scope)
        let privacy = PrivacySettingsStore(keyValue: kv, userScope: scope)
        let backupService: BackupService
        if options.inMemory {
            backupService = ICloudKeyValueBackup(keyValue: InMemoryKeyValueStore(), privacy: privacy, availability: { false })
        } else {
            backupService = ICloudKeyValueBackup.makeDefault(privacy: privacy)
        }

        if options.reset {
            UserDefaults.standard.removeObject(forKey: "storysounds.parentgate.lockout")
            try? DataDeletionService(store: store, localKeyValue: kv, privacy: privacy, backup: nil).deleteEverything()
        }

        var loaded: LearnerSnapshot?
        var failureText = failure
        if failure == nil {
            // Never reconcile (and therefore never save) against an empty fallback curriculum.
            switch ProfileSelection.choose(store: store, kv: kv) {
            case let .loaded(s):
                loaded = Migrator.reconcile(s, with: curriculum).snapshot
            case .empty:
                break
            case .unreadable:
                // Keep the unreadable bytes untouched; saving is disabled while `loadFailure` is set.
                failureText = AppEnvironment.progressUnreadableMessage
            }
        }
        let snap = loaded ?? AppEnvironment.freshSnapshot(contentVersion: curriculum.contentVersion)
        if failureText == nil { ProfileSelection.setActiveId(snap.profile.id, in: kv) }

        let lib = AudioLibrary(manifest: manifest)
        let backend: AudioBackend = options.noAudio ? SilentAudioBackend() : AVAudioPlayerBackend()
        let speech: SpeechFallback? = options.noAudio ? nil : AVSpeechFallback()
        let controller = AudioPlaybackController(library: lib, backend: backend, speech: speech, settings: snap.profile.settings)

        var on = true
        if !options.inMemory, let stored = UserDefaults.standard.object(forKey: AppEnvironment.soundKey) as? Bool { on = stored }
        controller.isMuted = !on

        self.options = options
        self.userScope = scope
        self.curriculum = curriculum
        self.index = CurriculumIndex(curriculum)
        self.manifest = manifest
        self.library = lib
        self.audio = controller
        self.store = store
        self.localKeyValue = kv
        self.privacy = privacy
        self.backup = backupService
        self.coordinator = PersistenceCoordinator(store: store)
        self.loadFailure = failureText
        self.snapshot = snap
        self.soundOn = on
        self.route = (loaded != nil) ? .home : .onboarding

        coordinator.onError = { [weak self] _ in
            Task { @MainActor [weak self] in self?.saveProblem = true }
        }
        coordinator.onSaved = { [weak self] _ in
            Task { @MainActor [weak self] in self?.saveProblem = false }
        }
        #if os(tvOS) || os(iOS) || os(visionOS)
        if !options.noAudio { sessionObserver = AVAudioSessionObserver(controller: controller) }
        #endif
    }

    // MARK: Time

    /// "Now" for planning and recording. Shifted by `-uitest-day-offset` / `-uitest-fast-review`.
    var now: Date { Date().addingTimeInterval(Double(options.dayOffset) * 86_400) }

    // MARK: Snapshot access

    /// Mutates the snapshot, publishes it and schedules a (debounced, compacted) save.
    func update(_ mutate: (inout LearnerSnapshot) -> Void) {
        var s = snapshot
        mutate(&s)
        snapshot = s
        if loadFailure == nil { coordinator.update(s) }
    }

    var settings: LearnerSettings { snapshot.profile.settings }

    func setSettings(_ newValue: LearnerSettings) {
        update { $0.profile.settings = newValue }
        audio.settings = newValue
    }

    /// True when motion should be removed everywhere: gentle mode on, or forced for tests.
    /// (Views also honour the system Reduce Motion setting through `accessibilityReduceMotion`.)
    var calmMotion: Bool { options.reduceMotion || snapshot.profile.settings.gentleMode }

    func setGentleMode(_ on: Bool) {
        var s = settings
        s.gentleMode = on
        setSettings(s)
    }

    func setSoundOn(_ on: Bool) {
        soundOn = on
        audio.isMuted = !on
        if !on { cancelSequence() }
        if !options.inMemory { UserDefaults.standard.set(on, forKey: AppEnvironment.soundKey) }
    }

    // MARK: Parent-facing helpers

    func explainUnits() -> [UnitExplanation] {
        Progression.explainUnits(index: index, snapshot: snapshot, now: now)
    }

    func parentReport() -> ParentReport {
        let explained = explainUnits()
        var statuses: [String: UnitStatus] = [:]
        for e in explained { statuses[e.unitId] = e.status }
        let current = Progression.nextUnit(index: index, snapshot: snapshot, now: now)?.id
        return ParentReport.make(curriculum: curriculum, snapshot: snapshot, now: now,
                                 inputs: ReportInputs(unitStatuses: statuses, currentUnitId: current))
    }

    /// Clears learning progress. Keeps profile id, nickname, creation date and settings.
    func resetProgress() {
        update { s in
            s.skills = []
            s.attempts = []
            s.confusions = []
            s.sessions = []
            s.profile.stickers = []
            s.profile.overrides = []
            s.profile.baselineDone = false
            s.profile.baselinePlacementOrder = nil
        }
        coordinator.flushNow()
    }

    /// Removes every learner snapshot, privacy setting and iCloud backup (DataDeletionService).
    /// On success the in-memory state is replaced by a fresh, UNSAVED profile; the caller decides when to move on
    /// (set `route = .onboarding`). Throws the first error so a grown-up is told the truth.
    /// Pending changes are dropped only AFTER the deletion succeeded; if it fails the last known state is re-armed
    /// so nothing the child just did is lost.
    func deleteEverything() throws {
        // Stop a debounced save from re-creating the profile in the middle of the deletion.
        coordinator.cancelPending()
        stopNarration()
        let service = DataDeletionService(store: store, localKeyValue: localKeyValue, privacy: privacy, backup: backup)
        do {
            try service.deleteEverything()
        } catch {
            if loadFailure == nil { coordinator.update(snapshot) }
            throw error
        }
        let fresh = AppEnvironment.freshSnapshot(contentVersion: curriculum.contentVersion)
        snapshot = fresh
        ProfileSelection.setActiveId(fresh.profile.id, in: localKeyValue)
        soundOn = true
        audio.isMuted = false
        audio.settings = fresh.profile.settings
        saveProblem = false
    }

    /// Applies a restored iCloud backup to the local store (same-id profiles are overwritten), then switches the app
    /// to the restored profile (the most recently used one when the backup holds several) and remembers that choice.
    /// Returns how many profiles were written. Throws so the parent is told the truth if restore fails.
    /// The latest unsaved changes are flushed BEFORE the store is touched, so a failed restore loses nothing.
    func restoreFromBackup(_ payload: BackupPayload) throws -> Int {
        if loadFailure == nil { coordinator.flushNow() }
        let written = try BackupRestoration.apply(payload, to: store, curriculum: curriculum, overwrite: true)
        var best: LearnerSnapshot?
        for id in written {
            guard let candidate = try store.load(profileId: id) else { continue }
            if let b = best, ProfileSelection.recency(b) >= ProfileSelection.recency(candidate) { continue }
            best = candidate
        }
        if let restored = best {
            snapshot = Migrator.reconcile(restored, with: curriculum).snapshot
            audio.settings = snapshot.profile.settings
            ProfileSelection.setActiveId(snapshot.profile.id, in: localKeyValue)
        }
        return written.count
    }

    /// Backup controller handed to the parent area through the SwiftUI environment (`\.parentBackup`).
    private(set) lazy var parentBackup: ParentBackupAdapter = ParentBackupAdapter(
        service: backup, privacy: privacy,
        snapshots: { [weak self] in self.map { [$0.snapshot] } ?? [] },
        restore: { [weak self] payload in try self?.restoreFromBackup(payload) ?? 0 })

    /// Call when the scene becomes inactive or backgrounded.
    func flush() {
        if loadFailure == nil { coordinator.flushNow() }
    }

    func sceneLeftForeground() {
        flush()
        stopNarration()
    }

    // MARK: Recording

    /// Folds one attempt into mastery, the attempt log and (for wrong choices) the confusion table.
    func recordAttempt(_ attempt: Attempt) {
        let masterySettings = snapshot.profile.settings.mastery
        let when = now
        update { s in
            if let i = s.skills.firstIndex(where: { $0.unitId == attempt.unitId && $0.track == attempt.track }) {
                s.skills[i] = Mastery.update(skill: s.skills[i], attempt: attempt, settings: masterySettings, now: when)
            } else {
                let fresh = SkillState(unitId: attempt.unitId, track: attempt.track)
                s.skills.append(Mastery.update(skill: fresh, attempt: attempt, settings: masterySettings, now: when))
            }
            s.attempts.append(attempt)
            if !attempt.correct, let expected = attempt.expected, let chosen = attempt.chosen, expected != chosen {
                if let c = s.confusions.firstIndex(where: { $0.expected == expected && $0.chosen == chosen }) {
                    s.confusions[c].count += 1
                    s.confusions[c].lastAt = when
                } else {
                    s.confusions.append(ConfusionRecord(expected: expected, chosen: chosen, count: 1, lastAt: when))
                }
            }
        }
    }

    /// Adds a sticker id to the profile when not already owned. Returns true when it was new.
    @discardableResult
    func awardSticker(_ id: String) -> Bool {
        if snapshot.profile.stickers.contains(id) { return false }
        update { $0.profile.stickers.append(id) }
        return true
    }

    func masteredUnitIds() -> Set<String> {
        Set(explainUnits().filter { $0.status == .mastered }.map { $0.unitId })
    }

    func phoneme(ofUnit unitId: String) -> String {
        index.unit(id: unitId)?.phoneme ?? ""
    }

    // MARK: Audio helpers

    @discardableResult
    func playAudio(_ id: String, slow: Bool = false) -> PlaybackResult {
        let result = audio.play(id, options: PlaybackOptions(slow: slow))
        if case let .captionOnly(label) = result, library.entry(for: id)?.kind == .phoneme {
            showSoundCaption(label)
        }
        return result
    }

    /// A child's own action (tapping a sound or a word) takes over from any prompt that is still being read out.
    @discardableResult
    func playAudioInterrupting(_ id: String, slow: Bool = false) -> PlaybackResult {
        interruptPrompt()
        return playAudio(id, slow: slow)
    }

    /// Plays ids one after another. A new call replaces the previous one: everything still playing or queued
    /// (including text-to-speech) is stopped first, so prompts never overlap or pile up. The wait after each clip is
    /// an estimate from the clip kind and text length because the audio controller does not report completion.
    /// Returns a token; pass it to `cancelSequence(token:)` so a screen only cancels its own prompt.
    @discardableResult
    func playSequence(_ ids: [String], slow: Bool = false) -> Int {
        sequenceTask?.cancel()
        sequenceGeneration += 1
        let generation = sequenceGeneration
        audio.stopAll()
        clearSoundCaption()
        sequenceTask = Task { @MainActor [weak self] in
            for (n, id) in ids.enumerated() {
                guard let strong = self, !Task.isCancelled, strong.sequenceGeneration == generation else { return }
                if n > 0 { strong.audio.stopAll() }
                let result = strong.playAudio(id, slow: slow)
                let seconds = strong.estimatedSeconds(for: id, result: result, slow: slow)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
        return generation
    }

    /// Stops the running prompt sequence only (not the sound that is playing right now).
    func cancelSequence() {
        sequenceTask?.cancel()
        sequenceTask = nil
    }

    /// Cancels and silences narration, but only if `token` still names the current sequence. A screen that is
    /// going away calls this so it cannot cut off the prompt of the screen that replaced it.
    func cancelSequence(token: Int) {
        guard token == sequenceGeneration else { return }
        stopNarration()
    }

    /// Stops the prompt sequence, any speech and every sound. Use when leaving an activity or the scene.
    func stopNarration() {
        cancelSequence()
        sequenceGeneration += 1
        audio.stopAll()
        clearSoundCaption()
    }

    /// Cuts off the rest of a prompt because the child acted. Keeps the caption (it explains what was just tapped).
    func interruptPrompt() {
        cancelSequence()
        sequenceGeneration += 1
        audio.stopAll()
    }

    private func estimatedSeconds(for id: String, result: PlaybackResult, slow: Bool) -> Double {
        let kind = library.entry(for: id)?.kind
        var seconds: Double
        switch result {
        case let .spokenPlaceholder(text):
            let words = Double(text.split(separator: " ").count)
            seconds = max(1.0, 0.7 + words * 0.42)
        case .played:
            seconds = (kind == .instruction) ? 2.4 : (kind == .phoneme ? 1.0 : 1.2)
        case .captionOnly:
            seconds = (kind == .phoneme) ? 1.6 : 0.4
        case .unavailable:
            seconds = 0.2
        }
        if slow { seconds *= 1.4 }
        return seconds
    }

    // MARK: Captions and announcements

    private func showSoundCaption(_ label: String) {
        // The announcement is for VoiceOver users and does not depend on the on-screen caption setting.
        announce("Sound \(AccessibilityText.spoken(label))")
        guard settings.showCaptions else { return }
        soundCaption = label
        captionTask?.cancel()
        // Long enough for a young reader (or a parent) to read; it is replaced by the next sound or prompt.
        captionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if !Task.isCancelled { self?.soundCaption = nil }
        }
    }

    private func clearSoundCaption() {
        captionTask?.cancel()
        captionTask = nil
        if soundCaption != nil { soundCaption = nil }
    }

    /// Speaks a status change to VoiceOver (feedback, "do it together" steps, sound captions). No-op otherwise.
    func announce(_ text: String) {
        #if canImport(UIKit)
        guard !text.isEmpty, UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
        #endif
    }
}
